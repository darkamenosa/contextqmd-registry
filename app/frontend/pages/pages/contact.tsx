import { Mail, MapPin, MessageSquare } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import PublicLayout from "@/layouts/public-layout"

const contactInfo = [
  {
    icon: Mail,
    title: "Email",
    detail: "hello@contextqmd.com",
    description: "We respond within 24 hours.",
  },
  {
    icon: MessageSquare,
    title: "Live Chat",
    detail: "Available 9am–6pm EST",
    description: "Talk to our support team.",
  },
  {
    icon: MapPin,
    title: "Office",
    detail: "San Francisco, CA",
    description: "Come say hello.",
  },
]

export default function Contact() {
  return (
    <PublicLayout title="Contact">
      <section className="mx-auto max-w-7xl px-4 py-20 sm:px-6 lg:px-8">
        <div className="grid gap-16 lg:grid-cols-2">
          {/* Left: Info */}
          <div>
            <p className="text-sm font-medium tracking-widest text-muted-foreground uppercase">
              Contact
            </p>
            <h1 className="mt-3 text-4xl font-bold tracking-tight">
              Get in touch
            </h1>
            <p className="mt-4 text-lg text-muted-foreground">
              Have a question, need a demo, or just want to chat? We&apos;d love
              to hear from you.
            </p>

            <div className="mt-12 flex flex-col gap-8">
              {contactInfo.map((item) => (
                <div key={item.title} className="flex gap-4">
                  <div className="flex size-11 shrink-0 items-center justify-center rounded-lg bg-muted">
                    <item.icon className="size-4" />
                  </div>
                  <div>
                    <h3 className="text-sm font-semibold">{item.title}</h3>
                    <p className="text-sm font-medium">{item.detail}</p>
                    <p className="text-sm text-muted-foreground">
                      {item.description}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Right: Form */}
          <div className="rounded-2xl border bg-card p-8">
            <h2 className="text-lg font-semibold">Send us a message</h2>
            <p className="mt-1 text-sm text-muted-foreground">
              Fill out the form and we&apos;ll get back to you shortly.
            </p>
            <form className="mt-6 flex flex-col gap-5">
              <div className="grid gap-5 sm:grid-cols-2">
                <div className="flex flex-col gap-2">
                  <Label htmlFor="firstName">First name</Label>
                  <Input id="firstName" placeholder="Jane" />
                </div>
                <div className="flex flex-col gap-2">
                  <Label htmlFor="lastName">Last name</Label>
                  <Input id="lastName" placeholder="Doe" />
                </div>
              </div>
              <div className="flex flex-col gap-2">
                <Label htmlFor="email">Email</Label>
                <Input id="email" type="email" placeholder="jane@example.com" />
              </div>
              <div className="flex flex-col gap-2">
                <Label htmlFor="message">Message</Label>
                <Textarea
                  id="message"
                  placeholder="Tell us how we can help..."
                  rows={5}
                />
              </div>
              <Button type="submit" size="lg" className="w-full">
                Send Message
              </Button>
            </form>
          </div>
        </div>
      </section>
    </PublicLayout>
  )
}
