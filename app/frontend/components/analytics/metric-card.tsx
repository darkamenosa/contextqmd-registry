import {
  CategoryScale,
  Chart as ChartJS,
  Filler,
  Legend,
  LinearScale,
  LineElement,
  PointElement,
  Title,
  Tooltip,
} from "chart.js"
import { ArrowDownIcon, ArrowUpIcon } from "lucide-react"
import { Line } from "react-chartjs-2"

import { Card, CardContent } from "@/components/ui/card"

// Register Chart.js components
ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler
)

type SparklineSeries = number[] | { today: number[]; yesterday?: number[] }

type MetricCardProps = {
  title: string
  value: string | number
  change?: number
  sparklineData?: SparklineSeries
  variant?: "default" | "large"
  showChange?: boolean
}

export function MetricCard({
  title,
  value,
  change,
  sparklineData,
  variant = "default",
  showChange = true,
}: MetricCardProps) {
  const hasChange = change !== undefined && change !== null && !isNaN(change)
  const isPositive = hasChange && change > 0
  const isNegative = hasChange && change < 0
  const normalized = Array.isArray(sparklineData)
    ? { today: sparklineData, yesterday: undefined as number[] | undefined }
    : sparklineData || { today: [], yesterday: undefined }
  const showSparkline = normalized.today && normalized.today.length > 0
  const hasMeaningfulChange = isPositive || isNegative

  return (
    <Card className="overflow-hidden rounded-lg border border-border bg-card !py-0">
      <CardContent className="px-4 py-3">
        <div className="flex flex-col gap-2">
          <span className="text-sm/5 font-semibold text-muted-foreground">
            {title}
          </span>

          <div className="grid grid-cols-2 items-center gap-3">
            <div className="flex items-baseline gap-2">
              <span
                className={
                  variant === "large"
                    ? "text-xl/7 font-semibold text-foreground"
                    : "text-lg/7 font-semibold text-foreground"
                }
              >
                {value}
              </span>

              {showChange &&
                (hasMeaningfulChange ? (
                  <div className="flex items-center gap-1 text-xs/4">
                    {isPositive && (
                      <ArrowUpIcon className="size-3 text-emerald-600 dark:text-emerald-400" />
                    )}
                    {isNegative && (
                      <ArrowDownIcon className="size-3 text-rose-600 dark:text-rose-400" />
                    )}
                    <span
                      className={
                        isPositive
                          ? "text-emerald-600 dark:text-emerald-400"
                          : "text-rose-600 dark:text-rose-400"
                      }
                    >
                      {Math.abs(change ?? 0)}%
                    </span>
                  </div>
                ) : (
                  <span className="text-xs/4 font-medium text-muted-foreground">
                    —
                  </span>
                ))}
            </div>

            {showSparkline && (
              <div className="ml-auto h-8 w-full max-w-[92px] overflow-hidden rounded-md">
                <Line
                  data={{
                    labels: Array.from(
                      {
                        length: Math.max(
                          normalized.today.length,
                          normalized.yesterday?.length || 0
                        ),
                      },
                      (_, i) => i
                    ),
                    datasets: [
                      ...(normalized.yesterday &&
                      normalized.yesterday.length > 0
                        ? [
                            {
                              data: normalized.yesterday,
                              borderColor: "rgba(128, 128, 128, 0.4)",
                              backgroundColor: "transparent",
                              borderWidth: 1,
                              borderDash: [3, 3] as [number, number],
                              pointRadius: 0,
                              pointHoverRadius: 0,
                              tension: 0.45,
                              fill: false,
                            },
                          ]
                        : []),
                      {
                        data: normalized.today,
                        borderColor: "rgba(26, 26, 26, 1)",
                        backgroundColor: "rgba(26, 26, 26, 0.06)",
                        borderWidth: 1.3,
                        pointRadius: 0,
                        pointHoverRadius: 0,
                        tension: 0.45,
                        fill: true,
                      },
                    ],
                  }}
                  options={{
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                      legend: { display: false },
                      tooltip: { enabled: false },
                    },
                    scales: {
                      x: { display: false },
                      y: { display: false, beginAtZero: true, grace: "20%" },
                    },
                    interaction: {
                      mode: "index",
                      intersect: false,
                    },
                  }}
                />
              </div>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  )
}
