import { useEffect, useState } from "react"

import { getConsumer, type Subscription } from "@/lib/cable"

import { sortInitialEvents } from "../lib/live-utils"
import type { LiveStats } from "../types"

export function liveStatsChannelIdentifier(subscriptionToken?: string | null) {
  return {
    channel: "AnalyticsChannel",
    subscription_token: subscriptionToken || undefined,
  }
}

export function useLiveStats(
  initialStats: LiveStats,
  subscriptionToken?: string | null
) {
  const [stats, setStats] = useState(() => sortInitialEvents(initialStats))
  const [connectionStatus, setConnectionStatus] = useState<
    "connected" | "disconnected" | "connecting"
  >("connecting")

  useEffect(() => {
    const consumer = getConsumer()
    const subscription = consumer.subscriptions.create(
      liveStatsChannelIdentifier(subscriptionToken),
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
  }, [subscriptionToken])

  return {
    stats,
    setStats,
    connectionStatus,
  }
}
