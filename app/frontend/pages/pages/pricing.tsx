import { Link } from "@inertiajs/react"
import { Check } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import PublicLayout from "@/layouts/public-layout"

const plans = [
  {
    name: "Starter",
    price: "$0",
    description: "For individuals and small side projects.",
    features: [
      "Up to 3 projects",
      "Basic analytics",
      "Community support",
      "1 GB storage",
    ],
    cta: "Get Started",
    popular: false,
  },
  {
    name: "Pro",
    price: "$20",
    period: "/mo",
    description: "For growing teams that need more power.",
    features: [
      "Unlimited projects",
      "Advanced analytics",
      "Priority support",
      "50 GB storage",
      "Custom integrations",
      "Team collaboration",
    ],
    cta: "Start Free Trial",
    popular: true,
  },
  {
    name: "Enterprise",
    price: "Custom",
    description: "For organizations with advanced needs.",
    features: [
      "Everything in Pro",
      "Unlimited storage",
      "SSO & SAML",
      "Dedicated account manager",
      "Custom SLA",
      "On-premise deployment",
    ],
    cta: "Contact Sales",
    popular: false,
  },
]

const faqs = [
  {
    q: "Can I change plans later?",
    a: "Yes, you can upgrade or downgrade at any time. Changes take effect immediately.",
  },
  {
    q: "What happens after my trial ends?",
    a: "You'll be moved to the free Starter plan. No charges unless you choose to upgrade.",
  },
  {
    q: "Do you offer refunds?",
    a: "Yes, we offer a 30-day money-back guarantee on all paid plans.",
  },
  {
    q: "Is there a discount for annual billing?",
    a: "Yes, annual plans save you 20% compared to monthly billing.",
  },
]

export default function Pricing() {
  return (
    <PublicLayout title="Pricing">
      {/* Header */}
      <section className="mx-auto max-w-7xl px-4 pt-20 pb-12 sm:px-6 lg:px-8">
        <div className="mx-auto max-w-2xl text-center">
          <p className="text-sm font-medium tracking-widest text-muted-foreground uppercase">
            Pricing
          </p>
          <h1 className="mt-3 text-4xl font-bold tracking-tight sm:text-5xl">
            Simple, transparent pricing
          </h1>
          <p className="mt-4 text-lg text-muted-foreground">
            Start free and scale as you grow. No hidden fees, no surprises.
          </p>
        </div>
      </section>

      {/* Plans */}
      <section className="mx-auto max-w-7xl px-4 pb-24 sm:px-6 lg:px-8">
        <div className="grid items-start gap-8 md:grid-cols-3">
          {plans.map((plan) => (
            <div
              key={plan.name}
              className={`rounded-2xl border p-8 ${
                plan.popular
                  ? "border-foreground bg-foreground text-background shadow-2xl"
                  : "bg-card"
              }`}
            >
              <div className="flex items-center justify-between">
                <h3 className="text-lg font-semibold">{plan.name}</h3>
                {plan.popular && (
                  <Badge variant="secondary" className="font-medium">
                    Most Popular
                  </Badge>
                )}
              </div>
              <p
                className={`mt-2 text-sm ${plan.popular ? "text-background/70" : "text-muted-foreground"}`}
              >
                {plan.description}
              </p>
              <div className="mt-6 flex items-baseline gap-1">
                <span className="text-4xl font-bold">{plan.price}</span>
                {plan.period && (
                  <span
                    className={
                      plan.popular
                        ? "text-background/70"
                        : "text-muted-foreground"
                    }
                  >
                    {plan.period}
                  </span>
                )}
              </div>
              <Button
                className="mt-6 w-full"
                variant={plan.popular ? "secondary" : "outline"}
                size="lg"
                nativeButton={false}
                render={
                  <Link
                    href={plan.name === "Enterprise" ? "/contact" : "/register"}
                  />
                }
              >
                {plan.cta}
              </Button>
              <ul className="mt-8 flex flex-col gap-3">
                {plan.features.map((feature) => (
                  <li key={feature} className="flex items-center gap-3 text-sm">
                    <Check
                      className={`size-4 shrink-0 ${plan.popular ? "text-background/70" : "text-muted-foreground"}`}
                    />
                    {feature}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </section>

      {/* FAQ */}
      <section className="border-t">
        <div className="mx-auto max-w-3xl px-4 py-24 sm:px-6 lg:px-8">
          <h2 className="text-center text-3xl font-bold tracking-tight sm:text-4xl">
            Frequently asked questions
          </h2>
          <div className="mt-12 grid gap-8 sm:grid-cols-2">
            {faqs.map((faq) => (
              <div key={faq.q}>
                <h3 className="text-sm font-semibold">{faq.q}</h3>
                <p className="mt-2 text-sm text-muted-foreground">{faq.a}</p>
              </div>
            ))}
          </div>
        </div>
      </section>
    </PublicLayout>
  )
}
