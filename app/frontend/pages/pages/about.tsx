import { Code2, Heart, Lightbulb } from "lucide-react"

import PublicLayout from "@/layouts/public-layout"

const values = [
  {
    icon: Lightbulb,
    title: "Simplicity First",
    description:
      "We believe the best tools stay out of your way. Every feature is designed to reduce complexity, not add to it.",
  },
  {
    icon: Heart,
    title: "Customer Obsessed",
    description:
      "Our users are our north star. We ship fast, listen carefully, and iterate relentlessly based on real feedback.",
  },
  {
    icon: Code2,
    title: "Craft Matters",
    description:
      "We sweat the details. From pixel-perfect interfaces to rock-solid infrastructure, quality is non-negotiable.",
  },
]

export default function About() {
  return (
    <PublicLayout title="About">
      {/* Hero */}
      <section className="mx-auto max-w-7xl px-4 pt-20 pb-12 sm:px-6 lg:px-8">
        <div className="mx-auto max-w-3xl">
          <p className="text-sm font-medium tracking-widest text-muted-foreground uppercase">
            About
          </p>
          <h1 className="mt-3 text-4xl font-bold tracking-tight sm:text-5xl">
            Building the future of team collaboration
          </h1>
          <div className="mt-8 space-y-6 text-lg/relaxed text-muted-foreground">
            <p>
              ContextQMD was founded with a simple belief: teams should
              spend their time building great products, not wrestling with
              tools. We&apos;re building the platform we always wished existed.
            </p>
            <p>
              We&apos;re a small, focused team distributed across the globe. We
              ship fast, stay close to our users, and believe that the best
              software comes from people who genuinely care about the problems
              they&apos;re solving.
            </p>
          </div>
        </div>
      </section>

      {/* Values */}
      <section className="border-t">
        <div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
          <div className="mx-auto max-w-2xl text-center">
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              What we believe in
            </h2>
          </div>
          <div className="mt-16 grid gap-8 md:grid-cols-3">
            {values.map((value) => (
              <div key={value.title} className="text-center">
                <div className="mx-auto flex size-11 items-center justify-center rounded-lg bg-muted">
                  <value.icon className="size-5 text-foreground" />
                </div>
                <h3 className="mt-5 text-lg font-semibold">{value.title}</h3>
                <p className="mt-2 text-sm/relaxed text-muted-foreground">
                  {value.description}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>
    </PublicLayout>
  )
}
