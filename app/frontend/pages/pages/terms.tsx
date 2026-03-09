import PublicLayout from "@/layouts/public-layout"

export default function Terms() {
  return (
    <PublicLayout title="Terms of Service">
      <section className="mx-auto max-w-3xl px-4 py-20 sm:px-6 lg:px-8">
        <p className="text-sm font-medium tracking-widest text-muted-foreground uppercase">
          Legal
        </p>
        <h1 className="mt-3 text-4xl font-bold tracking-tight">
          Terms of Service
        </h1>
        <p className="mt-4 text-sm text-muted-foreground">
          Last updated: January 1, 2026
        </p>
        <div className="mt-12 space-y-8 text-sm/relaxed text-muted-foreground">
          <div>
            <h2 className="text-base font-semibold text-foreground">
              1. Acceptance of Terms
            </h2>
            <p className="mt-3">
              By accessing or using ContextQMD, you agree to be bound by
              these Terms of Service. If you do not agree to these terms, please
              do not use our platform.
            </p>
          </div>
          <div>
            <h2 className="text-base font-semibold text-foreground">
              2. Use of Service
            </h2>
            <p className="mt-3">
              You may use our service only for lawful purposes and in accordance
              with these Terms. You agree not to use the service in any way that
              violates applicable laws or regulations.
            </p>
          </div>
          <div>
            <h2 className="text-base font-semibold text-foreground">
              3. Accounts
            </h2>
            <p className="mt-3">
              You are responsible for maintaining the confidentiality of your
              account credentials and for all activities that occur under your
              account.
            </p>
          </div>
          <div>
            <h2 className="text-base font-semibold text-foreground">
              4. Intellectual Property
            </h2>
            <p className="mt-3">
              The service and its original content, features, and functionality
              are owned by ContextQMD and are protected by international
              copyright, trademark, and other intellectual property laws.
            </p>
          </div>
          <div>
            <h2 className="text-base font-semibold text-foreground">
              5. Limitation of Liability
            </h2>
            <p className="mt-3">
              In no event shall ContextQMD be liable for any indirect,
              incidental, special, consequential, or punitive damages arising
              out of or related to your use of the service.
            </p>
          </div>
          <div>
            <h2 className="text-base font-semibold text-foreground">
              6. Contact Us
            </h2>
            <p className="mt-3">
              If you have any questions about these Terms, please contact us at
              legal@contextqmd_registry.app.
            </p>
          </div>
        </div>
      </section>
    </PublicLayout>
  )
}
