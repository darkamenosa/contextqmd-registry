import { cellToBoundary, cellToLatLng } from "h3-js"
import type * as THREE from "three"
import ConicPolygonGeometry from "three-conic-polygon-geometry"
import * as BufferGeometryUtils from "three/examples/jsm/utils/BufferGeometryUtils.js"

type HexGeometryOptions = {
  margin: number
  altitude: number
}

export function buildMergedHexGeometry(
  cells: readonly string[],
  { margin, altitude }: HexGeometryOptions
): THREE.BufferGeometry | null {
  if (cells.length === 0) return null

  const geometries: THREE.BufferGeometry[] = []

  for (const cell of cells) {
    const [centerLat, centerLng] = cellToLatLng(cell)
    const boundary = cellToBoundary(cell, true).slice().reverse()

    const shrunk =
      margin === 0
        ? boundary
        : boundary.map(([lng, lat]: [number, number]) => [
            lerp(lng, centerLng, margin),
            lerp(lat, centerLat, margin),
          ])

    try {
      geometries.push(
        new ConicPolygonGeometry(
          [shrunk],
          1,
          1 + altitude,
          false,
          true,
          false,
          4
        )
      )
    } catch {
      // Ignore malformed cells so a single bad cell does not break the layer.
    }
  }

  if (geometries.length === 0) return null

  const merged = BufferGeometryUtils.mergeGeometries(
    geometries,
    false
  ) as THREE.BufferGeometry

  geometries.forEach((geometry) => geometry.dispose())

  return merged
}

function lerp(a: number, b: number, t: number) {
  return a * (1 - t) + b * t
}
