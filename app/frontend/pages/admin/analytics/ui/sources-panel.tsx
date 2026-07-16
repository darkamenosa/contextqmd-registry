import { Bug } from "lucide-react"

import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"

import { useSourcesPanelController } from "../hooks/use-sources-panel-controller"
import type { SourcesMode } from "../lib/dialog-path"
import { SOURCES_CAMPAIGN_OPTIONS } from "../lib/sources-panel"
import type { ListItem, ListMetricKey, ListPayload } from "../types"
import DetailsButton from "./details-button"
import { MetricTable, PanelEmptyState, PanelListSkeleton } from "./list-table"
import { PanelTab, PanelTabDropdown, PanelTabs } from "./panel-tabs"
import RemoteDetailsDialog from "./remote-details-dialog"
import SourceDebugDialog from "./source-debug-dialog"
import { SourceIcon } from "./sources-panel/source-icon"
import { buildSourceExternalLink } from "./sources-panel/source-link"

type SourcesPanelProps = {
  initialData: ListPayload
  initialMode: string
}

function renderSourceIcon(item: ListItem) {
  const name = String(item.name ?? "").trim()
  return <SourceIcon name={name} />
}

export default function SourcesPanel({
  initialData,
  initialMode,
}: SourcesPanelProps) {
  const {
    activeSource,
    campaignActive,
    campaignLabel,
    cardTitle,
    data,
    debugOpen,
    detailsOpen,
    dialogTitle,
    firstColumnLabel,
    handlePrimaryRowClick,
    handleReferrerRowClick,
    highlightMetric,
    isGoogleActive,
    limitedData,
    limitedTermsData,
    loading,
    mode,
    openDetailsDialog,
    refData,
    refDetailsOpen,
    refLoading,
    searchTermsStatus,
    selectedSearchTermsPage,
    setAndStoreMode,
    setDebugOpen,
    setLast28Days,
    searchTermsEndpoint,
    showSourceIcon,
    sourcesEndpoint,
    sourceDebugSource,
    syncPrimaryDialog,
    syncReferrerDialog,
    takeover,
    termsData,
    termsError,
    termsErrorCode,
    termsLoading,
    utmHasUsableData,
    referrersEndpoint,
  } = useSourcesPanelController({
    initialData,
    initialMode,
  })

  const isOverviewEmpty = data.results.length === 0 || !utmHasUsableData

  return (
    <section
      className="flex flex-col gap-3 rounded-lg border border-border bg-card p-4"
      data-testid="sources-panel"
    >
      <SourcesPanelHeader
        cardTitle={cardTitle}
        takeover={takeover}
        mode={mode}
        campaignActive={campaignActive}
        campaignLabel={campaignLabel}
        onSelectMode={setAndStoreMode}
      />

      {loading ? (
        <PanelListSkeleton firstColumnLabel={firstColumnLabel} />
      ) : takeover === "referrers" ? (
        <ReferrersTakeoverContent
          data={refData}
          loading={refLoading}
          onRowClick={handleReferrerRowClick}
          onOpenDetails={openDetailsDialog}
        />
      ) : takeover === "search-terms" ? (
        <SearchTermsTakeoverContent
          data={termsData}
          limitedData={limitedTermsData}
          loading={termsLoading}
          error={termsError}
          errorCode={termsErrorCode}
          status={searchTermsStatus}
          selectedPage={selectedSearchTermsPage}
          onOpenDetails={openDetailsDialog}
          onSelectLast28Days={setLast28Days}
        />
      ) : isOverviewEmpty ? (
        <PanelEmptyState />
      ) : (
        <SourcesOverviewContent
          data={limitedData}
          highlightedMetric={highlightMetric ?? "visitors"}
          activeSource={activeSource}
          firstColumnLabel={firstColumnLabel}
          showSourceIcon={showSourceIcon}
          onInspect={() => setDebugOpen(true)}
          onOpenDetails={openDetailsDialog}
          onRowClick={handlePrimaryRowClick}
        />
      )}

      <RemoteDetailsDialog
        open={detailsOpen}
        onOpenChange={syncPrimaryDialog}
        title={isGoogleActive ? "Google search terms" : dialogTitle}
        endpoint={isGoogleActive ? searchTermsEndpoint : sourcesEndpoint}
        extras={isGoogleActive ? {} : { mode }}
        firstColumnLabel={isGoogleActive ? "Search term" : firstColumnLabel}
        defaultSortKey={"visitors"}
        onRowClick={
          isGoogleActive
            ? undefined
            : (item) => handlePrimaryRowClick(item, true)
        }
        renderLeading={
          isGoogleActive || !showSourceIcon ? undefined : renderSourceIcon
        }
        sortable
      />

      {activeSource && !isGoogleActive ? (
        <RemoteDetailsDialog
          open={refDetailsOpen}
          onOpenChange={syncReferrerDialog}
          title="Referrer Drilldown"
          endpoint={referrersEndpoint}
          extras={{ source: activeSource }}
          firstColumnLabel="Referrer"
          defaultSortKey={"visitors"}
          onRowClick={(item) => handleReferrerRowClick(item, true)}
          renderLeading={renderSourceIcon}
          getExternalLinkUrl={(item) =>
            buildSourceExternalLink(String(item.name))
          }
        />
      ) : null}

      <SourceDebugDialog
        open={debugOpen}
        onOpenChange={setDebugOpen}
        source={sourceDebugSource}
      />
    </section>
  )
}

function SourcesPanelHeader({
  cardTitle,
  takeover,
  mode,
  campaignActive,
  campaignLabel,
  onSelectMode,
}: {
  cardTitle: string
  takeover: "none" | "referrers" | "search-terms"
  mode: SourcesMode
  campaignActive: boolean
  campaignLabel: string
  onSelectMode: (mode: SourcesMode) => void
}) {
  return (
    <header className="flex flex-wrap items-center justify-between gap-3">
      <h2 className="text-base font-medium">{cardTitle}</h2>
      {takeover === "none" ? (
        <PanelTabs>
          <PanelTab
            active={mode === "channels"}
            onClick={() => onSelectMode("channels")}
          >
            Channels
          </PanelTab>
          <PanelTab active={mode === "all"} onClick={() => onSelectMode("all")}>
            Sources
          </PanelTab>
          <PanelTabDropdown
            active={campaignActive}
            label={campaignLabel}
            options={SOURCES_CAMPAIGN_OPTIONS}
            onSelect={(value) => onSelectMode(value as SourcesMode)}
          />
        </PanelTabs>
      ) : null}
    </header>
  )
}

function ReferrersTakeoverContent({
  data,
  loading,
  onRowClick,
  onOpenDetails,
}: {
  data: ListPayload | null
  loading: boolean
  onRowClick: (item: ListItem) => void
  onOpenDetails: () => void
}) {
  if (loading) {
    return <PanelListSkeleton firstColumnLabel="Referrer" />
  }

  if (!data || data.results.length === 0) {
    return <PanelEmptyState />
  }

  return (
    <>
      <MetricTable
        data={{ ...data, metrics: ["visitors"] as ListMetricKey[] }}
        firstColumnLabel="Referrer"
        renderLeading={renderSourceIcon}
        displayBars={false}
        barColorTheme="cyan"
        testId="referrers"
        onRowClick={onRowClick}
      />
      <div className="mt-auto flex justify-center pt-3">
        <DetailsButton
          data-testid="sources-details-btn"
          onClick={onOpenDetails}
        >
          Details
        </DetailsButton>
      </div>
    </>
  )
}

function SearchTermsTakeoverContent({
  data,
  limitedData,
  loading,
  error,
  errorCode,
  status,
  selectedPage,
  onOpenDetails,
  onSelectLast28Days,
}: {
  data: ListPayload | null
  limitedData: ListPayload | null
  loading: boolean
  error: string | null
  errorCode: string | null
  status: ListPayload["meta"]["searchConsole"] | undefined
  selectedPage: string | null
  onOpenDetails: () => void
  onSelectLast28Days: () => void
}) {
  if (loading) {
    return <PanelListSkeleton firstColumnLabel="Search term" />
  }

  if (data && data.results.length > 0) {
    return (
      <>
        <SearchTermsStatusNote status={status} />
        <MetricTable
          data={
            limitedData
              ? {
                  ...limitedData,
                  metrics: ["visitors"] as ListMetricKey[],
                }
              : {
                  ...data,
                  metrics: ["visitors"] as ListMetricKey[],
                }
          }
          firstColumnLabel="Search term"
          displayBars={false}
          barColorTheme="cyan"
          testId="search-terms"
        />
        <div className="mt-auto flex justify-center pt-3">
          <DetailsButton onClick={onOpenDetails}>Details</DetailsButton>
        </div>
      </>
    )
  }

  if (error) {
    return (
      <PanelEmptyState>
        <div className="flex flex-col items-center gap-4 text-center">
          <div className="text-lg font-semibold text-foreground">
            {errorCode === "period_too_recent"
              ? "Select a different period"
              : "Search Terms"}
          </div>
          <div className="max-w-prose text-sm text-muted-foreground">
            {error}
          </div>
          {errorCode === "period_too_recent" ? (
            <Button onClick={onSelectLast28Days}>Search last 28 days</Button>
          ) : null}
        </div>
      </PanelEmptyState>
    )
  }

  if (status?.syncInProgress) {
    return (
      <PanelEmptyState>
        <div className="flex flex-col items-center gap-4 text-center">
          <div className="text-lg font-semibold text-foreground">
            Search Terms
          </div>
          <div className="max-w-prose text-sm text-muted-foreground">
            Search Console sync is in progress for{" "}
            {status.refreshWindowFrom ?? "?"} to {status.refreshWindowTo ?? "?"}
            . Results will appear after the sync completes.
          </div>
        </div>
      </PanelEmptyState>
    )
  }

  if (status?.syncStale) {
    return (
      <PanelEmptyState>
        <div className="flex flex-col items-center gap-4 text-center">
          <div className="text-lg font-semibold text-foreground">
            Search Terms
          </div>
          <div className="max-w-prose text-sm text-muted-foreground">
            Search Console data for this site needs a refresh. Open analytics
            settings to retry the sync, then come back here.
          </div>
        </div>
      </PanelEmptyState>
    )
  }

  return (
    <PanelEmptyState>
      <div className="flex flex-col items-center gap-4 text-center">
        <div className="text-lg font-semibold text-foreground">
          {selectedPage
            ? "No keywords found for filtered paths"
            : "Search Terms"}
        </div>
        <div className="max-w-prose text-sm text-muted-foreground">
          {selectedPage ? (
            <>
              No search terms rank for the selected path:
              <br />
              <span className="font-medium text-foreground">
                {selectedPage}
              </span>
              <br />
              Try a different path or remove the filter.
            </>
          ) : (
            "No Google search terms matched this period and filter set."
          )}
        </div>
      </div>
    </PanelEmptyState>
  )
}

function SourcesOverviewContent({
  data,
  highlightedMetric,
  activeSource,
  firstColumnLabel,
  showSourceIcon,
  onInspect,
  onOpenDetails,
  onRowClick,
}: {
  data: ListPayload
  highlightedMetric: ListMetricKey
  activeSource: string | undefined
  firstColumnLabel: string
  showSourceIcon: boolean
  onInspect: () => void
  onOpenDetails: () => void
  onRowClick: (item: ListItem) => void
}) {
  return (
    <>
      <MetricTable
        data={data}
        highlightedMetric={highlightedMetric}
        onRowClick={onRowClick}
        renderLeading={showSourceIcon ? renderSourceIcon : undefined}
        displayBars={false}
        firstColumnLabel={firstColumnLabel}
        barColorTheme="cyan"
        revealSecondaryMetricsOnHover
        testId="sources"
      />
      <div className="mt-auto flex justify-center pt-3">
        <div className="flex items-center gap-2">
          {activeSource ? (
            <Button
              variant="outline"
              size="sm"
              className="gap-2"
              onClick={onInspect}
            >
              <Bug className="size-3.5" />
              Inspect
            </Button>
          ) : null}
          <DetailsButton
            data-testid="sources-details-btn"
            onClick={onOpenDetails}
          >
            Details
          </DetailsButton>
        </div>
      </div>
    </>
  )
}

function SearchTermsStatusNote({
  status,
}: {
  status: ListPayload["meta"]["searchConsole"] | undefined
}) {
  if (!status?.configured) return null

  if (status.reauthRequired && status.connectionError) {
    return (
      <Alert variant="destructive">
        <AlertDescription>{status.connectionError}</AlertDescription>
      </Alert>
    )
  }

  if (status.syncInProgress) {
    return (
      <Alert>
        <AlertDescription>
          Search Console sync is in progress for{" "}
          {status.refreshWindowFrom ?? "?"} to {status.refreshWindowTo ?? "?"}.
        </AlertDescription>
      </Alert>
    )
  }

  if (status.syncError) {
    return (
      <Alert>
        <AlertDescription>
          Search Console sync last failed: {status.syncError}
        </AlertDescription>
      </Alert>
    )
  }

  if (status.syncStale) {
    return (
      <Alert>
        <AlertDescription>
          Search Console data is stale. The latest refresh window ends on{" "}
          {status.refreshWindowTo ?? "?"}.
        </AlertDescription>
      </Alert>
    )
  }

  return null
}
