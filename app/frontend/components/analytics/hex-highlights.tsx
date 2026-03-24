import { useEffect, useMemo, useRef } from "react"
import { useThree } from "@react-three/fiber"
import { cellToBoundary, cellToLatLng, latLngToCell } from "h3-js"
import * as THREE from "three"
import ConicPolygonGeometry from "three-conic-polygon-geometry"
// three's BufferGeometryUtils helper for merging many hex geometries into one
import * as BufferGeometryUtils from "three/examples/jsm/utils/BufferGeometryUtils.js"

type Dot = {
  lat: number
  lng: number
  type: "visitor" | "order"
  city?: string | null
}

type Props = {
  data: Dot[]
  resolution?: number
  margin?: number
  // Base altitude just above land hexes (land ~0.002). Layers are stacked:
  // order > visitor > land
  altitudeBase?: number
  onHover?: (t: { x: number; y: number; label: string } | null) => void
}

// Draws real hexes (same geometry/orientation as the land layer) at the H3 cell
// containing each dot. This guarantees exact alignment with the grid at all zooms.
export default function HexHighlights({
  data,
  resolution = 3,
  margin = 0.2,
  altitudeBase = 0.00205,
  onHover,
}: Props) {
  const { scene, camera, gl } = useThree()
  const groupRef = useRef<THREE.Group | null>(null)

  const { visitorCells, cellLabels } = useMemo(() => {
    const v = new Set<string>()
    const labels = new Map<string, string>()
    for (const d of data) {
      try {
        const cell = latLngToCell(d.lat, d.lng, resolution)
        v.add(cell)
        if (!labels.has(cell)) labels.set(cell, (d.city || "Unknown") as string)
      } catch {
        // Ignore invalid coordinates; they simply do not render on the globe.
      }
    }
    return { visitorCells: Array.from(v), cellLabels: labels }
  }, [data, resolution])

  useEffect(() => {
    const group = new THREE.Group()
    group.renderOrder = 2

    const makeLayer = (
      cells: string[],
      color: string,
      altitude: number,
      renderOrder: number,
      options?: { outline?: boolean }
    ) => {
      if (cells.length === 0) return
      const geoms: THREE.BufferGeometry[] = []
      for (const idx of cells) {
        // Get hex boundary and center
        const center = cellToLatLng(idx) // [lat,lng]
        const centerLat = center[0]
        const centerLng = center[1]
        let boundary = cellToBoundary(idx, true) // [[lng,lat], ...]
        // Ensure winding similar to three-globe (reverse)
        boundary = boundary.slice().reverse()

        // Apply same margin logic as three-globe to keep inner hex size consistent
        const shrink = (elng: number, elat: number) => {
          const lerp = (a: number, b: number, t: number) => a * (1 - t) + b * t
          return [
            lerp(elng, centerLng, margin),
            lerp(elat, centerLat, margin),
          ] as [number, number]
        }
        const shrunk =
          margin === 0
            ? boundary
            : boundary.map(([lng, lat]) => shrink(lng, lat))

        // Build a single ConicPolygonGeometry for this hex from radius 1 to 1+altitude
        try {
          const geo = new ConicPolygonGeometry(
            [shrunk],
            1,
            1 + altitude,
            false,
            true,
            false,
            4
          )
          geoms.push(geo)
        } catch {
          // Ignore malformed cells so a single bad geometry does not break the layer.
        }
      }
      if (geoms.length > 0) {
        const merged = BufferGeometryUtils.mergeGeometries(
          geoms,
          false
        ) as THREE.BufferGeometry
        const mat = new THREE.MeshLambertMaterial({
          color,
          transparent: false,
          depthWrite: true,
        })
        const mesh = new THREE.Mesh(merged, mat)
        mesh.renderOrder = renderOrder
        group.add(mesh)

        if (options?.outline) {
          // Crisp 1px white outline above the fill
          const edges = new THREE.EdgesGeometry(merged)
          const lineMat = new THREE.LineBasicMaterial({
            color: "#ffffff",
            transparent: true,
            opacity: 0.95,
            depthTest: false,
          })
          const lines = new THREE.LineSegments(edges, lineMat)
          lines.renderOrder = renderOrder + 1
          group.add(lines)
        }
      }
    }

    const visitorAlt = altitudeBase + 0.00008
    makeLayer(visitorCells, "#2563eb", visitorAlt, 3)

    scene.add(group)
    groupRef.current = group

    return () => {
      if (groupRef.current) {
        scene.remove(groupRef.current)
        groupRef.current.traverse((obj) => {
          const mesh = obj as THREE.Mesh
          if (mesh.geometry) mesh.geometry.dispose?.()
          if (mesh.material) {
            const m = mesh.material as THREE.Material | THREE.Material[]
            if (Array.isArray(m)) {
              m.forEach((material) => material.dispose?.())
            } else {
              m.dispose?.()
            }
          }
        })
        groupRef.current = null
      }
    }
  }, [scene, visitorCells, margin, altitudeBase])

  // Pointer interaction: map cursor to globe point, then to H3 cell, then show label
  useEffect(() => {
    if (!onHover) return
    const sphereRadius = 1
    const handleMove = (ev: PointerEvent) => {
      const rect = gl.domElement.getBoundingClientRect()
      const nx = ((ev.clientX - rect.left) / rect.width) * 2 - 1
      const ny = -((ev.clientY - rect.top) / rect.height) * 2 + 1

      const ray = new THREE.Ray()
      ray.origin.copy((camera as THREE.PerspectiveCamera).position)
      ray.direction
        .set(nx, ny, 0.5)
        .unproject(camera as THREE.PerspectiveCamera)
        .sub(ray.origin)
        .normalize()

      // Ray-sphere intersection (center at 0, radius=1)
      const o = ray.origin
      const d = ray.direction
      const b = o.dot(d)
      const c = o.lengthSq() - sphereRadius * sphereRadius
      const disc = b * b - c
      if (disc < 0) {
        onHover(null)
        return
      }
      const t = -b - Math.sqrt(disc)
      if (t <= 0) {
        onHover(null)
        return
      }
      const p = new THREE.Vector3().copy(d).multiplyScalar(t).add(o)

      // Convert to lat/lng
      const r = p.length()
      const phi = Math.acos(p.y / r)
      const theta = Math.atan2(p.z, p.x)
      const lat = 90 - (phi * 180) / Math.PI
      const lng =
        90 - (theta * 180) / Math.PI - (theta < -Math.PI / 2 ? 360 : 0)

      try {
        const cell = latLngToCell(lat, lng, resolution)
        if (cellLabels.has(cell)) {
          const label = cellLabels.get(cell) as string
          onHover({
            x: ev.clientX - rect.left + 10,
            y: ev.clientY - rect.top + 12,
            label,
          })
          return
        }
      } catch {
        // Ignore hover points that do not map cleanly to an H3 cell.
      }
      onHover(null)
    }
    const leave = () => onHover(null)
    gl.domElement.addEventListener("pointermove", handleMove)
    gl.domElement.addEventListener("pointerleave", leave)
    return () => {
      gl.domElement.removeEventListener("pointermove", handleMove)
      gl.domElement.removeEventListener("pointerleave", leave)
    }
  }, [camera, gl, onHover, cellLabels, resolution])

  return null
}
