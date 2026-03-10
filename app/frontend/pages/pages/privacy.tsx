import PublicLayout from "@/layouts/public-layout"

export default function Privacy() {
  return (
    <PublicLayout title="Privacy Policy">
      <section className="mx-auto max-w-3xl px-4 py-20 sm:px-6 lg:px-8">
        <p className="text-sm font-medium tracking-widest text-muted-foreground uppercase">
          Legal
        </p>
        <h1 className="mt-3 text-4xl font-bold tracking-tight">
          Privacy Policy
        </h1>
        <p className="mt-4 text-sm text-muted-foreground">
          Last updated: March 2026
        </p>
        <div className="mt-12 space-y-8 text-sm/relaxed text-muted-foreground">
          <div>
            <h2 className="text-base font-semibold text-foreground">
              1. Information We Collect
            </h2>
            <p className="mt-3">
              We collect information you provide directly, such as when you
              create an account, fill out a form, or contact us. This may
              include your name, email address, and any other information you
              choose to provide.
            </p>
          </div>
          <div>
            <h2 className="text-base font-semibold text-foreground">
              2. How We Use Your Information
            </h2>
            <p className="mt-3">
              We use the information we collect to provide, maintain, and
              improve our services, to communicate with you, and to protect our
              users.
            </p>
          </div>
          <div>
            <h2 className="text-base font-semibold text-foreground">
              3. Information Sharing
            </h2>
            <p className="mt-3">
              We do not sell your personal information. We may share information
              with third-party service providers who help us operate our
              platform, subject to confidentiality obligations.
            </p>
          </div>
          <div>
            <h2 className="text-base font-semibold text-foreground">
              4. Data Security
            </h2>
            <p className="mt-3">
              We implement appropriate technical and organizational measures to
              protect your personal information against unauthorized access,
              alteration, disclosure, or destruction.
            </p>
          </div>
          <div>
            <h2 className="text-base font-semibold text-foreground">
              5. Contact Us
            </h2>
            <p className="mt-3">
              If you have any questions about this Privacy Policy, please
              contact us at privacy@contextqmd.com.
            </p>
          </div>
        </div>
      </section>
    </PublicLayout>
  )
}
