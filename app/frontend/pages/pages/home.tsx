import { Link } from "@inertiajs/react"
import { ArrowRight, BarChart3, Shield, Zap } from "lucide-react"

import { Button } from "@/components/ui/button"
import PublicLayout from "@/layouts/public-layout"

const features = [
  {
    icon: Zap,
    title: "Lightning Fast",
    description:
      "Built for speed from the ground up. Every interaction feels instant, every page loads in milliseconds.",
  },
  {
    icon: Shield,
    title: "Secure by Default",
    description:
      "Enterprise-grade security with encryption at rest and in transit. SOC 2 compliant out of the box.",
  },
  {
    icon: BarChart3,
    title: "Actionable Insights",
    description:
      "Real-time analytics and reporting that help you make data-driven decisions with confidence.",
  },
]

const stats = [
  { value: "10k+", label: "Active Users" },
  { value: "99.9%", label: "Uptime" },
  { value: "150+", label: "Countries" },
  { value: "4.9/5", label: "Rating" },
]

export default function Home() {
  return (
    <PublicLayout title="Home">
      {/* Hero */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 -z-10 bg-[radial-gradient(circle_at_30%_20%,_var(--muted)_0%,_transparent_50%)]" />
        <div className="mx-auto max-w-7xl px-4 pt-20 pb-24 sm:px-6 sm:pt-28 sm:pb-32 lg:px-8">
          <div className="mx-auto max-w-3xl text-center">
            <p className="text-sm font-medium tracking-widest text-muted-foreground uppercase">
              The modern platform for teams
            </p>
            <h1 className="mt-4 text-5xl font-bold tracking-tight sm:text-7xl">
              Build better,{" "}
              <span className="text-muted-foreground">ship faster</span>
            </h1>
            <p className="mx-auto mt-6 max-w-xl text-lg/relaxed text-muted-foreground">
              The all-in-one platform that helps your team collaborate,
              automate, and scale — without the complexity.
            </p>
            <div className="mt-10 flex items-center justify-center gap-4">
              <Button
                size="lg"
                nativeButton={false}
                render={<Link href="/register" />}
              >
                Get Started Free
                <ArrowRight className="size-4" />
              </Button>
              <Button
                variant="outline"
                size="lg"
                nativeButton={false}
                render={<Link href="/pricing" />}
              >
                View Pricing
              </Button>
            </div>
          </div>
        </div>
      </section>

      {/* Stats */}
      <section className="border-y bg-muted/30">
        <div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 lg:px-8">
          <div className="grid grid-cols-2 gap-8 md:grid-cols-4">
            {stats.map((stat) => (
              <div key={stat.label} className="text-center">
                <div className="text-3xl font-bold tracking-tight">
                  {stat.value}
                </div>
                <div className="mt-1 text-sm text-muted-foreground">
                  {stat.label}
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
        <div className="mx-auto max-w-2xl text-center">
          <p className="text-sm font-medium tracking-widest text-muted-foreground uppercase">
            Features
          </p>
          <h2 className="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">
            Everything you need to succeed
          </h2>
          <p className="mt-4 text-muted-foreground">
            Powerful tools designed to help your team move faster and build
            better products.
          </p>
        </div>

        <div className="mt-16 grid gap-8 md:grid-cols-3">
          {features.map((feature) => (
            <div
              key={feature.title}
              className="group rounded-2xl border bg-card p-8 transition-colors hover:border-foreground/20"
            >
              <div className="flex size-11 items-center justify-center rounded-lg bg-primary text-primary-foreground">
                <feature.icon className="size-5" />
              </div>
              <h3 className="mt-5 text-lg font-semibold">{feature.title}</h3>
              <p className="mt-2 text-sm/relaxed text-muted-foreground">
                {feature.description}
              </p>
            </div>
          ))}
        </div>
      </section>

      {/* CTA */}
      <section className="border-t">
        <div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
          <div className="mx-auto max-w-2xl text-center">
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              Ready to get started?
            </h2>
            <p className="mt-4 text-lg text-muted-foreground">
              Join thousands of teams already using ContextqmdRegistry to build
              and ship faster.
            </p>
            <div className="mt-8 flex items-center justify-center gap-4">
              <Button
                size="lg"
                nativeButton={false}
                render={<Link href="/register" />}
              >
                Start Free Trial
                <ArrowRight className="size-4" />
              </Button>
              <Button
                variant="ghost"
                size="lg"
                nativeButton={false}
                render={<Link href="/contact" />}
              >
                Talk to Sales
              </Button>
            </div>
            <p className="mt-4 text-xs text-muted-foreground">
              No credit card required. 14-day free trial.
            </p>
          </div>
        </div>
      </section>
    </PublicLayout>
  )
}
