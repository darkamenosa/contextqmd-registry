export function liveStatsChannelIdentifier(subscriptionToken?: string | null) {
  return {
    channel: "AnalyticsChannel",
    subscription_token: subscriptionToken || undefined,
  }
}
