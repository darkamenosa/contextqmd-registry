import { useEffect, useMemo, useRef } from "react"
import globeData from "@/data/globe-data.json"
import { useThree } from "@react-three/fiber"
import type {
  Feature,
  FeatureCollection,
  GeoJsonProperties,
  Geometry,
} from "geojson"
import ThreeGlobe from "three-globe"

// Import as GeoJSON FeatureCollection
const rawFeatures = globeData as unknown as FeatureCollection<
  Geometry,
  GeoJsonProperties
>

export default function HexLandLayer() {
  const { scene } = useThree()
  const globeRef = useRef<ThreeGlobe | null>(null)

  const landFeatures = useMemo(() => {
    if (!rawFeatures?.features)
      return [] as Feature<Geometry, GeoJsonProperties>[]

    // Features are already individual Polygons with holes removed from build script
    return rawFeatures.features as Feature<Geometry, GeoJsonProperties>[]
  }, [])

  useEffect(() => {
    if (!landFeatures.length) return

    const globe = new ThreeGlobe({ animateIn: false })
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    globe.hexPolygonsData(landFeatures as any)
    globe.hexPolygonResolution(3) // Medium resolution hexagons
    globe.hexPolygonMargin(0.2) // Small margin for tight spacing
    globe.hexPolygonUseDots(false) // Use filled hexagons, not dots
    const SCALE = 0.01
    globe.hexPolygonAltitude(() => 0.002) // Slight elevation
    // In-between Tailwind sky-300 and sky-400 (~"sky-350") for softer contrast
    globe.hexPolygonColor(() => "#5ac8fa")
    globe.hexPolygonsTransitionDuration(0)
    globe.showAtmosphere(false)
    globe.scale.setScalar(SCALE)

    const baseMaterial = globe.globeMaterial()
    baseMaterial.transparent = true
    baseMaterial.opacity = 0
    baseMaterial.depthWrite = false

    // Access and configure hexagon material for better rendering
    const hexMaterialAccessor =
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (globe as unknown as { hexPolygonsMaterial?: () => any })
        .hexPolygonsMaterial
    if (hexMaterialAccessor) {
      const mat = hexMaterialAccessor.call(globe)
      mat.transparent = false
      mat.opacity = 1.0
      mat.depthWrite = true
    }

    globeRef.current = globe
    scene.add(globe)

    return () => {
      scene.remove(globe)
      globeRef.current = null
    }
  }, [landFeatures, scene])

  return null
}
