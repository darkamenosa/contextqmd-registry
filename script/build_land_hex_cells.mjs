import fs from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"

import { polygonToCells } from "h3-js"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const rootDir = path.resolve(__dirname, "..")
const inputPath = path.join(rootDir, "app/frontend/data/globe-data.json")
const outputPath = path.join(rootDir, "app/frontend/data/land-hex-cells.json")
const resolution = 3

const source = JSON.parse(await fs.readFile(inputPath, "utf8"))
const cells = new Set()

for (const feature of source.features ?? []) {
  collectGeometryCells(feature.geometry, resolution, cells)
}

const output = `${JSON.stringify(Array.from(cells).sort(), null, 2)}\n`
await fs.writeFile(outputPath, output)

function collectGeometryCells(geometry, res, target) {
  if (!geometry) return

  if (geometry.type === "Polygon") {
    addPolygonCells(geometry.coordinates, res, target)
    return
  }

  if (geometry.type === "MultiPolygon") {
    for (const polygon of geometry.coordinates) {
      addPolygonCells(polygon, res, target)
    }
  }
}

function addPolygonCells(coordinates, res, target) {
  for (const cell of polygonToCells(coordinates, res, true)) {
    target.add(cell)
  }
}
