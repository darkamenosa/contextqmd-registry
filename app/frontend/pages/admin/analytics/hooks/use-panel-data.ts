import {
  startTransition,
  useEffect,
  useEffectEvent,
  useRef,
  useState,
} from "react"

type UsePanelDataOptions<T> = {
  initialData: T
  initialRequestKey: string
  requestKey: string
  fetchData: (controller: AbortController) => Promise<T>
}

export function usePanelData<T>({
  initialData,
  initialRequestKey,
  requestKey,
  fetchData,
}: UsePanelDataOptions<T>) {
  const [data, setData] = useState<T>(initialData)
  const [loading, setLoading] = useState(false)
  const lastRequestKeyRef = useRef(initialRequestKey)
  const activeRequestIdRef = useRef(0)
  const runFetch = useEffectEvent((controller: AbortController) =>
    fetchData(controller)
  )

  useEffect(() => {
    if (requestKey === lastRequestKeyRef.current) return
    lastRequestKeyRef.current = requestKey

    const controller = new AbortController()
    const requestId = activeRequestIdRef.current + 1
    activeRequestIdRef.current = requestId
    startTransition(() => setLoading(true))

    runFetch(controller)
      .then((nextData) => {
        if (activeRequestIdRef.current !== requestId) return
        setData(nextData)
      })
      .catch((error) => {
        if (error.name !== "AbortError") console.error(error)
      })
      .finally(() => {
        if (activeRequestIdRef.current !== requestId) return
        setLoading(false)
      })

    return () => controller.abort()
  }, [requestKey])

  return {
    data,
    setData,
    loading,
  }
}
