import { useEffect, useMemo, useRef } from "react"
import landHexCells from "@/data/land-hex-cells.json"
import { useThree } from "@react-three/fiber"
import * as THREE from "three"

import { buildMergedHexGeometry } from "@/lib/h3-hex-geometry"

export default function HexLandLayer() {
  const { scene } = useThree()
  const meshRef = useRef<THREE.Mesh | null>(null)
  const geometry = useMemo(
    () =>
      buildMergedHexGeometry(landHexCells, {
        margin: 0.2,
        altitude: 0.002,
      }),
    []
  )

  useEffect(() => {
    if (!geometry) return

    const material = new THREE.MeshLambertMaterial({
      color: "#5ac8fa",
      transparent: false,
      depthWrite: true,
    })
    const mesh = new THREE.Mesh(geometry, material)
    mesh.renderOrder = 1

    meshRef.current = mesh
    scene.add(mesh)

    return () => {
      scene.remove(mesh)
      material.dispose()
      meshRef.current = null
    }
  }, [geometry, scene])

  useEffect(
    () => () => {
      geometry?.dispose()
    },
    [geometry]
  )

  return null
}
