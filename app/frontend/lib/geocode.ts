export type GeocodeResult = { name: string; lat: number; lng: number }
export type GeocodeOptions = {
  countryCodes?: string[]
  biasLng?: number
  biasWidthDeg?: number
  limit?: number
  placeTypes?: string[]
}

export async function geocodeOsm(
  query: string,
  optsOrSignal?: GeocodeOptions | AbortSignal,
  maybeSignal?: AbortSignal
): Promise<GeocodeResult[]> {
  const opts: GeocodeOptions | undefined =
    optsOrSignal instanceof AbortSignal ? undefined : optsOrSignal
  const signal: AbortSignal | undefined =
    (optsOrSignal instanceof AbortSignal ? optsOrSignal : maybeSignal) ||
    undefined

  const url = new URL("https://nominatim.openstreetmap.org/search")
  url.searchParams.set("format", "jsonv2")
  url.searchParams.set("q", query)
  url.searchParams.set("limit", String(opts?.limit ?? 5))
  url.searchParams.set("email", "noreply@contextqmd.com")
  if (opts?.countryCodes?.length) {
    url.searchParams.set("countrycodes", opts.countryCodes.join(","))
  }
  if (typeof opts?.biasLng === "number") {
    const width = Math.max(30, Math.min(180, opts.biasWidthDeg ?? 160))
    const left = normalizeLng(opts.biasLng - width / 2)
    const right = normalizeLng(opts.biasLng + width / 2)
    if (left < right) {
      url.searchParams.set("viewbox", `${left},${85},${right},${-85}`)
    }
  }
  const res = await fetch(url.toString(), {
    headers: { "Accept-Language": navigator.language || "en" },
    method: "GET",
    signal,
  })
  if (!res.ok) return []
  const data = await res.json()
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let rows: any[] = Array.isArray(data) ? data : []
  const defaultPlaceTypes = opts?.placeTypes ?? [
    "city",
    "town",
    "village",
    "hamlet",
    "suburb",
    "locality",
    "municipality",
    "borough",
    "county",
    "state",
    "region",
    "province",
    "country",
  ]
  const placeRows = rows.filter(
    (d) =>
      d &&
      d.category === "place" &&
      defaultPlaceTypes.includes(d.type || d.addresstype)
  )
  if (placeRows.length) rows = placeRows
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return rows.map((d: any) => ({
    name: d.display_name as string,
    lat: parseFloat(d.lat),
    lng: parseFloat(d.lon),
  }))
}

function normalizeLng(lng: number) {
  let x = ((((lng + 180) % 360) + 360) % 360) - 180
  if (x === -180) x = 180
  return x
}
