import { useCallback, useEffect, useRef, useState } from "react"

type UseClientComponentOptions = {
  preload?: boolean
}

export function useClientComponent<TComponent>(
  loader: () => Promise<TComponent>,
  options: UseClientComponentOptions = {}
) {
  const { preload = false } = options
  const mountedRef = useRef(true)
  const inFlightRef = useRef<Promise<TComponent> | null>(null)
  const [component, setComponent] = useState<TComponent | null>(null)

  useEffect(() => {
    return () => {
      mountedRef.current = false
    }
  }, [])

  const load = useCallback(() => {
    if (component) return Promise.resolve(component)
    if (inFlightRef.current) return inFlightRef.current

    const pending = loader()
      .then((loaded) => {
        if (mountedRef.current) {
          setComponent(() => loaded)
        }

        return loaded
      })
      .finally(() => {
        inFlightRef.current = null
      })

    inFlightRef.current = pending
    return pending
  }, [component, loader])

  useEffect(() => {
    if (!preload) return

    void load().catch((error) => {
      console.error("Failed to load client component", error)
    })
  }, [load, preload])

  return {
    Component: component,
    load,
    loaded: component !== null,
  }
}
