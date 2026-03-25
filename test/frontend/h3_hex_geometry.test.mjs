import assert from "node:assert/strict"
import { mkdtemp, rm } from "node:fs/promises"
import { createRequire } from "node:module"
import { tmpdir } from "node:os"
import path from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"
import { build } from "esbuild"

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..")
const require = createRequire(import.meta.url)

async function loadGeometryModule() {
  const workdir = await mkdtemp(path.join(tmpdir(), "h3-hex-geometry-"))
  const outfile = path.join(workdir, "h3-hex-geometry.cjs")
  const originalWindow = globalThis.window
  const originalSelf = globalThis.self

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: ["app/frontend/lib/h3-hex-geometry.ts"],
      format: "cjs",
      outfile,
      platform: "node",
      tsconfig: path.join(repoRoot, "tsconfig.app.json"),
    })

    globalThis.window = globalThis
    globalThis.self = globalThis

    return require(outfile)
  } finally {
    if (originalWindow === undefined) {
      delete globalThis.window
    } else {
      globalThis.window = originalWindow
    }

    if (originalSelf === undefined) {
      delete globalThis.self
    } else {
      globalThis.self = originalSelf
    }

    await rm(workdir, { force: true, recursive: true })
  }
}

function latLngToVector3(lat, lng, radius = 1) {
  const phi = (90 - lat) * (Math.PI / 180)
  const theta = (90 - lng) * (Math.PI / 180)
  const sinPhi = Math.sin(phi)

  return {
    x: radius * sinPhi * Math.cos(theta),
    y: radius * Math.cos(phi),
    z: radius * sinPhi * Math.sin(theta),
  }
}

function angleBetween(a, b) {
  const dot = a.x * b.x + a.y * b.y + a.z * b.z
  const magA = Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
  const magB = Math.sqrt(b.x * b.x + b.y * b.y + b.z * b.z)
  const cos = Math.max(-1, Math.min(1, dot / (magA * magB)))
  return (Math.acos(cos) * 180) / Math.PI
}

test("antimeridian seam cells stay local after margin shrink", async () => {
  const { buildMergedHexGeometry } = await loadGeometryModule()
  const geometry = buildMergedHexGeometry(["839b5dfffffffff"], {
    margin: 0.2,
    altitude: 0.002,
  })

  assert.ok(geometry)

  const position = geometry.getAttribute("position")
  const center = latLngToVector3(-16.27721260173814, 179.84375525072736, 1)

  let maxAngle = 0

  for (let i = 0; i < position.count; i += 1) {
    const vertex = {
      x: position.getX(i),
      y: position.getY(i),
      z: position.getZ(i),
    }
    maxAngle = Math.max(maxAngle, angleBetween(vertex, center))
  }

  geometry.dispose()

  // A res-3 H3 cell around Fiji should remain very local to its center.
  // The broken implementation produced vertices tens of degrees away.
  assert.ok(
    maxAngle < 5,
    `expected seam cell geometry to stay compact, got max angle ${maxAngle}`
  )
})
