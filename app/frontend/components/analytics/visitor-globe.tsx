/* eslint-disable react/no-unknown-property */
import {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
  useState,
} from "react"
import type React from "react"
import { OrbitControls } from "@react-three/drei"
import { Canvas } from "@react-three/fiber"
import { latLngToCell } from "h3-js"
import * as THREE from "three"
import type { OrbitControls as OrbitControlsImpl } from "three-stdlib"

import HexHighlights, {
  type HexHighlightSelection,
} from "@/components/analytics/hex-highlights"
import HexLandLayer from "@/components/analytics/hex-land-layer"

export const VISITOR_GLOBE_MIN_DISTANCE = 1.8
export const VISITOR_GLOBE_MAX_DISTANCE = 3.2
const ZOOM_STEP = 0.35
const VIEW_CHANGE_THROTTLE_MS = 120
const INITIAL_LAT = 39 // continental US
const INITIAL_LNG = -98
const INITIAL_DISTANCE = VISITOR_GLOBE_MAX_DISTANCE // start at farthest zoom

type VisitorDot = {
  lat: number
  lng: number
  type: "visitor" | "order"
  ts?: number // epoch ms; used for fading
  label?: string | null
  region?: string | null
  country?: string | null
  city?: string | null
}

type VisitorGlobeProps = {
  visitors: VisitorDot[]
  autoRotate?: boolean
  onZoomChange?: (state: VisitorGlobeZoomState) => void
  onViewChange?: (view: { lat: number; lng: number; distance: number }) => void
  onSelectCell?: (selection: HexHighlightSelection | null) => void
}

export type VisitorGlobeZoomState = {
  distance: number
  minDistance: number
  maxDistance: number
}

export type VisitorGlobeHandle = {
  zoomIn: () => void
  zoomOut: () => void
  getDistance: () => number
  focusOn: (lat: number, lng: number, distance?: number) => void
  flyTo: (
    lat: number,
    lng: number,
    distance?: number,
    durationMs?: number
  ) => Promise<void>
  getSelectionAnchor: (
    lat: number,
    lng: number,
    label?: string
  ) => HexHighlightSelection | null
  getView: () => { lat: number; lng: number; distance: number }
}

export const VisitorGlobe = forwardRef(function VisitorGlobe(
  {
    visitors,
    autoRotate = false,
    onZoomChange,
    onViewChange,
    onSelectCell,
  }: VisitorGlobeProps,
  ref: React.Ref<VisitorGlobeHandle>
) {
  // Tooltip removed for hex highlight approach; can be re-added later
  const controlsRef = useRef<OrbitControlsImpl>(null)
  const directionRef = useRef(new THREE.Vector3())
  const tempPositionRef = useRef(new THREE.Vector3())
  const rendererRef = useRef<THREE.WebGLRenderer | null>(null)
  const animationFrameRef = useRef<number | null>(null)
  const viewChangeTimeoutRef = useRef<number | null>(null)
  const lastViewChangeAtRef = useRef(0)
  const animationStateRef = useRef<
    | {
        kind: "distance"
        from: number
        to: number
        start: number | null
        duration: number
        resolve?: () => void
      }
    | {
        kind: "fly"
        fromDir: THREE.Vector3
        toDir: THREE.Vector3
        distance: number
        start: number | null
        duration: number
        resolve?: () => void
      }
    | null
  >(null)
  const [isInteracting, setIsInteracting] = useState(false)

  const getDistance = useCallback(() => {
    const controls = controlsRef.current
    if (!controls) return VISITOR_GLOBE_MAX_DISTANCE
    return (controls.object as THREE.PerspectiveCamera).position.distanceTo(
      controls.target
    )
  }, [])

  const cancelAnimation = useCallback(() => {
    const state = animationStateRef.current
    if (animationFrameRef.current !== null) {
      cancelAnimationFrame(animationFrameRef.current)
      animationFrameRef.current = null
    }
    state?.resolve?.()
    animationStateRef.current = null
  }, [])

  const emitZoomChange = useCallback(
    (distance?: number) => {
      if (!onZoomChange) return
      const currentDistance = distance ?? getDistance()
      onZoomChange({
        distance: currentDistance,
        minDistance: VISITOR_GLOBE_MIN_DISTANCE,
        maxDistance: VISITOR_GLOBE_MAX_DISTANCE,
      })
    },
    [getDistance, onZoomChange]
  )

  const emitViewChange = useCallback(() => {
    if (!onViewChange || !controlsRef.current) return
    const controls = controlsRef.current
    const distance = getDistance()
    const camera = controls.object as THREE.PerspectiveCamera
    const { lat, lng } = vector3ToLatLng(camera.position)
    onViewChange({ lat, lng, distance })
  }, [getDistance, onViewChange])

  const clearScheduledViewChange = useCallback(() => {
    if (viewChangeTimeoutRef.current !== null) {
      window.clearTimeout(viewChangeTimeoutRef.current)
      viewChangeTimeoutRef.current = null
    }
  }, [])

  const scheduleViewChange = useCallback(
    ({ immediate = false }: { immediate?: boolean } = {}) => {
      if (!onViewChange || !controlsRef.current) return

      const now = performance.now()
      const elapsed = now - lastViewChangeAtRef.current
      if (
        immediate ||
        lastViewChangeAtRef.current === 0 ||
        elapsed >= VIEW_CHANGE_THROTTLE_MS
      ) {
        clearScheduledViewChange()
        lastViewChangeAtRef.current = now
        emitViewChange()
        return
      }

      if (viewChangeTimeoutRef.current !== null) return

      viewChangeTimeoutRef.current = window.setTimeout(() => {
        viewChangeTimeoutRef.current = null
        lastViewChangeAtRef.current = performance.now()
        emitViewChange()
      }, VIEW_CHANGE_THROTTLE_MS - elapsed)
    },
    [clearScheduledViewChange, emitViewChange, onViewChange]
  )

  const applyDistance = useCallback(
    (distance: number, emit = true) => {
      const controls = controlsRef.current
      if (!controls) return

      const camera = controls.object as THREE.PerspectiveCamera
      directionRef.current
        .copy(camera.position)
        .sub(controls.target)
        .normalize()

      tempPositionRef.current
        .copy(directionRef.current)
        .multiplyScalar(distance)
        .add(controls.target)

      camera.position.copy(tempPositionRef.current)
      camera.updateProjectionMatrix()
      controls.update()
      if (emit) emitZoomChange(distance)
    },
    [emitZoomChange]
  )

  const animateToDistance = useCallback(
    (targetDistance: number) => {
      const controls = controlsRef.current
      if (!controls) return

      const from = getDistance()
      const to = THREE.MathUtils.clamp(
        targetDistance,
        VISITOR_GLOBE_MIN_DISTANCE,
        VISITOR_GLOBE_MAX_DISTANCE
      )

      if (Math.abs(to - from) < 0.001) {
        applyDistance(to)
        return
      }

      cancelAnimation()

      const duration = 280
      animationStateRef.current = {
        kind: "distance",
        from,
        to,
        start: null,
        duration,
      }

      const step = (timestamp: number) => {
        const state = animationStateRef.current
        if (!state) return

        if (state.kind !== "distance") return
        if (state.start === null) state.start = timestamp
        const progress = Math.min((timestamp - state.start) / state.duration, 1)
        const eased = progress * progress * (3 - 2 * progress) // smoothstep easing
        const distance = THREE.MathUtils.lerp(state.from, state.to, eased)

        // Emit on each frame so UI stays in sync.
        applyDistance(distance)

        if (progress < 1) {
          animationFrameRef.current = requestAnimationFrame(step)
        } else {
          animationFrameRef.current = null
          animationStateRef.current = null
        }
      }

      animationFrameRef.current = requestAnimationFrame(step)
    },
    [applyDistance, cancelAnimation, getDistance]
  )

  const zoomBy = useCallback(
    (delta: number) => {
      animateToDistance(getDistance() + delta)
    },
    [animateToDistance, getDistance]
  )

  const focusOn = useCallback(
    (lat: number, lng: number, distance?: number) => {
      const controls = controlsRef.current
      if (!controls) return
      const camera = controls.object as THREE.PerspectiveCamera
      // Keep target at origin so we orbit the globe, not a surface point
      controls.target.set(0, 0, 0)
      const d = distance ?? getDistance()
      camera.position.copy(latLngToVector3(lat, lng, d))
      camera.lookAt(0, 0, 0)
      camera.updateProjectionMatrix()
      controls.update()
      emitZoomChange(d)
      scheduleViewChange({ immediate: true })
    },
    [emitZoomChange, getDistance, scheduleViewChange]
  )

  const flyTo = useCallback(
    (lat: number, lng: number, distance?: number, durationMs?: number) => {
      const controls = controlsRef.current
      if (!controls) return Promise.resolve()
      const camera = controls.object as THREE.PerspectiveCamera
      controls.target.set(0, 0, 0)
      const from = vector3ToLatLng(camera.position)
      const targetDistance = distance ?? getDistance()

      // Shortest longitude path (handles wrapping across the antimeridian)
      let dLng = lng - from.lng
      if (dLng > 180) dLng -= 360
      if (dLng < -180) dLng += 360

      // Scale duration with total angular travel
      const totalAngle = Math.abs(lat - from.lat) + Math.abs(dLng) // rough arc degrees
      const minMs = 600
      const maxMs = 1800
      const autoDuration = minMs + (totalAngle / 360) * (maxMs - minMs)
      const duration = Math.max(
        300,
        Math.min(maxMs, durationMs ?? autoDuration)
      )

      return new Promise<void>((resolve) => {
        cancelAnimation()
        animationStateRef.current = {
          kind: "fly",
          fromDir: camera.position.clone().normalize(),
          toDir: latLngToVector3(lat, lng, 1).normalize(),
          distance: targetDistance,
          start: null,
          duration,
          resolve,
        }

        const fromLat = from.lat
        const fromLng = from.lng

        const step = (timestamp: number) => {
          const state = animationStateRef.current
          if (!state) return
          if (state.kind !== "fly") return
          if (state.start === null) state.start = timestamp
          const t = Math.min((timestamp - state.start) / state.duration, 1)
          // ease-in-out quad
          const eased = t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t

          // Interpolate lat/lng independently — this keeps the rotation
          // "around" the globe (horizontal) rather than cutting over the poles.
          const curLat = fromLat + (lat - fromLat) * eased
          const curLng = fromLng + dLng * eased
          const pos = latLngToVector3(curLat, curLng, state.distance)
          camera.position.copy(pos)
          camera.updateProjectionMatrix()
          controls.update()
          emitZoomChange(state.distance)
          scheduleViewChange()
          if (t < 1) {
            animationFrameRef.current = requestAnimationFrame(step)
          } else {
            animationFrameRef.current = null
            animationStateRef.current = null
            scheduleViewChange({ immediate: true })
            state.resolve?.()
          }
        }

        animationFrameRef.current = requestAnimationFrame(step)
      })
    },
    [cancelAnimation, emitZoomChange, getDistance, scheduleViewChange]
  )

  const getSelectionAnchor = useCallback(
    (lat: number, lng: number, label = "Unknown") => {
      const controls = controlsRef.current
      const renderer = rendererRef.current
      if (!controls || !renderer) return null

      const camera = controls.object as THREE.PerspectiveCamera
      const point = latLngToVector3(lat, lng, 1.01)
      const visibleHemisphere = point
        .clone()
        .normalize()
        .dot(camera.position.clone().normalize())

      if (visibleHemisphere <= 0) return null

      const projected = point.clone().project(camera)
      if (
        projected.z < -1 ||
        projected.z > 1 ||
        !Number.isFinite(projected.x) ||
        !Number.isFinite(projected.y)
      ) {
        return null
      }

      const rect = renderer.domElement.getBoundingClientRect()
      let cellId: string
      try {
        cellId = latLngToCell(lat, lng, 3)
      } catch {
        return null
      }

      return {
        cellId,
        label,
        x: ((projected.x + 1) / 2) * rect.width,
        y: ((1 - projected.y) / 2) * rect.height,
        width: rect.width,
        height: rect.height,
      }
    },
    []
  )

  useImperativeHandle(
    ref,
    () => ({
      zoomIn: () => zoomBy(-ZOOM_STEP),
      zoomOut: () => zoomBy(ZOOM_STEP),
      getDistance,
      focusOn,
      flyTo,
      getSelectionAnchor,
      getView: () => {
        const controls = controlsRef.current
        if (!controls)
          return {
            lat: INITIAL_LAT,
            lng: INITIAL_LNG,
            distance: INITIAL_DISTANCE,
          }
        const camera = controls.object as THREE.PerspectiveCamera
        const { lat, lng } = vector3ToLatLng(camera.position)
        return { lat, lng, distance: getDistance() }
      },
    }),
    [flyTo, focusOn, getDistance, getSelectionAnchor, zoomBy]
  )

  const [tooltip, setTooltip] = useState<{
    x: number
    y: number
    label: string
  } | null>(null)

  useEffect(() => {
    const controls = controlsRef.current
    if (!controls) return

    const handleStart = () => {
      setIsInteracting(true)
      setTooltip(null)
      clearScheduledViewChange()
      cancelAnimation()
    }
    const handleChange = () => {
      emitZoomChange()
      scheduleViewChange()
    }
    const handleEnd = () => {
      setIsInteracting(false)
      scheduleViewChange({ immediate: true })
    }
    controls.addEventListener("change", handleChange)
    controls.addEventListener("start", handleStart)
    controls.addEventListener("end", handleEnd)

    // Emit once on mount so parent syncs initial state
    emitZoomChange()
    scheduleViewChange({ immediate: true })

    return () => {
      controls.removeEventListener("end", handleEnd)
      controls.removeEventListener("start", handleStart)
      controls.removeEventListener("change", handleChange)
    }
  }, [
    cancelAnimation,
    clearScheduledViewChange,
    emitZoomChange,
    scheduleViewChange,
  ])

  useEffect(
    () => () => {
      clearScheduledViewChange()
      cancelAnimation()
    },
    [cancelAnimation, clearScheduledViewChange]
  )

  // Initial focus on the Americas, slightly closer, no auto-rotate by default
  useEffect(() => {
    if (controlsRef.current) {
      focusOn(INITIAL_LAT, INITIAL_LNG, INITIAL_DISTANCE)
    } else {
      // Defer one frame in case controls ref isn't ready yet
      const raf = requestAnimationFrame(() =>
        focusOn(INITIAL_LAT, INITIAL_LNG, INITIAL_DISTANCE)
      )
      return () => cancelAnimationFrame(raf)
    }
  }, [focusOn])

  return (
    <div className="relative h-full w-full overflow-hidden bg-muted">
      <Canvas
        className="relative z-10"
        camera={{ position: [0, 0, VISITOR_GLOBE_MAX_DISTANCE], fov: 45 }}
        gl={{ alpha: true, antialias: true }}
        onCreated={({ gl, camera }) => {
          rendererRef.current = gl
          gl.setClearColor(0x000000, 0)
          // Pre-orient the camera so the US faces forward even before OrbitControls attaches
          const dir = latLngToVector3(
            INITIAL_LAT,
            INITIAL_LNG,
            INITIAL_DISTANCE
          )
          ;(camera as THREE.PerspectiveCamera).position.copy(dir)
          ;(camera as THREE.PerspectiveCamera).lookAt(0, 0, 0)
        }}
      >
        <ambientLight intensity={1.05} color={new THREE.Color("#f1faff")} />
        <hemisphereLight args={["#c4f1f9", "#dbeafe", 0.9]} />

        <Globe />
        <Halo />
        <HexLandLayer />
        <HexHighlights
          data={visitors}
          hoverDisabled={isInteracting}
          onHover={setTooltip}
          onSelectCell={onSelectCell}
        />

        <OrbitControls
          ref={controlsRef}
          enableZoom
          enablePan={false}
          autoRotate={autoRotate}
          autoRotateSpeed={0.3}
          minDistance={VISITOR_GLOBE_MIN_DISTANCE}
          maxDistance={VISITOR_GLOBE_MAX_DISTANCE}
          zoomSpeed={0.45}
        />
      </Canvas>
      {tooltip && (
        <div
          className="pointer-events-none absolute z-20 rounded-sm bg-popover/90 px-2 py-1 text-xs text-foreground"
          style={{ left: tooltip.x, top: tooltip.y }}
        >
          {tooltip.label}
        </div>
      )}
    </div>
  )
})

function Globe() {
  const uniforms = useMemo(
    () => ({
      uColorTop: { value: new THREE.Color("#f3fbff") },
      uColorBottom: { value: new THREE.Color("#bde5ff") },
      uRimColor: { value: new THREE.Color("#e0faff") },
      uRimStrength: { value: 0.36 },
    }),
    []
  )

  return (
    <mesh>
      <sphereGeometry args={[1, 64, 64]} />
      <shaderMaterial
        transparent={false}
        uniforms={uniforms}
        vertexShader={`
          varying vec3 vNormal;
          varying vec3 vWorldPos;
          void main(){
            vNormal = normalize(normalMatrix * normal);
            vec4 wp = modelMatrix * vec4(position,1.0);
            vWorldPos = wp.xyz;
            gl_Position = projectionMatrix * viewMatrix * wp;
          }
        `}
        fragmentShader={`
          uniform vec3 uColorTop;
          uniform vec3 uColorBottom;
          uniform vec3 uRimColor;
          uniform float uRimStrength;
          varying vec3 vNormal;
          varying vec3 vWorldPos;
          void main(){
            float t = smoothstep(-0.25, 0.65, vNormal.y);
            vec3 base = mix(uColorBottom, uColorTop, t);
            float rim = pow(1.0 - max(dot(normalize(vNormal), vec3(0.0,0.0,1.0)), 0.0), 1.1);
            vec3 color = mix(base, uRimColor, rim * uRimStrength);
            gl_FragColor = vec4(color, 1.0);
          }
        `}
      />
    </mesh>
  )
}

// Subtle rim lighting to hide the aliased edge (GitHub-style halo)
function Halo() {
  const materialRef = useRef<THREE.ShaderMaterial>(null)
  return (
    <mesh>
      <sphereGeometry args={[1.01, 48, 48]} />
      <shaderMaterial
        ref={materialRef}
        transparent
        depthWrite={false}
        blending={THREE.AdditiveBlending}
        vertexShader={`
          varying vec3 vNormal;
          void main() {
            vNormal = normalize(normalMatrix * normal);
            gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
          }
        `}
        fragmentShader={`
          varying vec3 vNormal;
          void main() {
            float intensity = pow(1.0 - max(dot(vNormal, vec3(0.0, 0.0, 1.0)), 0.0), 1.05);
            gl_FragColor = vec4(0.93, 0.99, 1.0, intensity * 0.32);
          }
        `}
      />
    </mesh>
  )
}

// Removed sprite-based VisitorsPoints in favor of hex highlights

// Match three-globe's polar2Cartesian so our points align with its hex grid
// three-globe formula (before scaling):
//   phi   = (90 - lat) * DEG2RAD
//   theta = (90 - lng) * DEG2RAD
//   x = r * sin(phi) * cos(theta)
//   y = r * cos(phi)
//   z = r * sin(phi) * sin(theta)
function latLngToVector3(
  lat: number,
  lng: number,
  radius: number
): THREE.Vector3 {
  const phi = (90 - lat) * (Math.PI / 180)
  const theta = (90 - lng) * (Math.PI / 180)
  const sinPhi = Math.sin(phi)

  return new THREE.Vector3(
    radius * sinPhi * Math.cos(theta),
    radius * Math.cos(phi),
    radius * sinPhi * Math.sin(theta)
  )
}

function vector3ToLatLng(v: THREE.Vector3): { lat: number; lng: number } {
  const r = v.length()
  if (r === 0) return { lat: 0, lng: 0 }
  const y = v.y / r
  const phi = Math.acos(THREE.MathUtils.clamp(y, -1, 1))
  const theta = Math.atan2(v.z, v.x)
  const lat = 90 - (phi * 180) / Math.PI
  const lng = 90 - (theta * 180) / Math.PI
  const normLng = ((lng + 180) % 360) - 180
  return { lat, lng: normLng }
}
