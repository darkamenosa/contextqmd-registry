import { useEffect, useState } from "react"

import { getConsumer, type Subscription } from "@/lib/cable"

import { sortInitialEvents } from "../lib/live-utils"
import type { LiveStats } from "../types"

export function useLiveStats(initialStats: LiveStats) {
  const [stats, setStats] = useState(() => sortInitialEvents(initialStats))
  const [connectionStatus, setConnectionStatus] = useState<
    "connected" | "disconnected" | "connecting"
  >("connecting")

  useEffect(() => {
    const consumer = getConsumer()
    const subscription = consumer.subscriptions.create(
      { channel: "AnalyticsChannel" },
      {
        connected: () => {
          setConnectionStatus("connected")
        },
        disconnected: () => {
          setConnectionStatus("disconnected")
        },
        received: (data: LiveStats) => {
          setStats((prev) =>
            sortInitialEvents({
              ...prev,
              ...data,
            })
          )
        },
        rejected: () => {
          setConnectionStatus("disconnected")
          console.error("WebSocket connection rejected")
        },
      }
    ) as Subscription

    return () => {
      subscription.unsubscribe()
    }
  }, [])

  return {
    stats,
    setStats,
    connectionStatus,
  }
}
