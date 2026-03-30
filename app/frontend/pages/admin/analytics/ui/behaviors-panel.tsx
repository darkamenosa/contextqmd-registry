import { Input } from "@/components/ui/input"

import { useBehaviorsPanelController } from "../hooks/use-behaviors-panel-controller"
import { analyticsScopedPath } from "../lib/path-prefix"
import type { BottomPanelPayload, ListMetricKey } from "../types"
import FunnelSteps from "./behaviors-panel/funnel-steps"
import ProfilesList from "./behaviors-panel/profiles-list"
import SelectionTabDropdown from "./behaviors-panel/selection-tab-dropdown"
import DetailsButton from "./details-button"
import { MetricTable, PanelEmptyState, PanelListSkeleton } from "./list-table"
import { PanelTab, PanelTabs } from "./panel-tabs"
import ProfileJourneySheet from "./profile-journey-sheet"
import RemoteDetailsDialog from "./remote-details-dialog"

type BehaviorsPanelProps = {
  initialData: BottomPanelPayload
  initialMode?: string | null
  initialFunnel?: string | null
  initialProperty?: string | null
}

export default function BehaviorsPanel({
  initialData,
  initialMode,
  initialFunnel,
  initialProperty,
}: BehaviorsPanelProps) {
  const {
    activeProperty,
    activeTitle,
    availableFunnels,
    behaviourTabs,
    closeDetailsDialog,
    detailsOpen,
    firstColumnLabel,
    funnelData,
    handleRowClick,
    hasRenderableFunnels,
    journeyOpen,
    limitedTablePayload,
    loadMoreProfiles,
    loading,
    mode,
    openDetailsDialog,
    profilesData,
    profilesLoadingMore,
    profilesSearch,
    propertyOptions,
    selectedFunnel,
    selectedProfile,
    setAndStoreMode,
    setDetailsDialogOpen,
    setJourneyOpen,
    setProfilesSearch,
    setSelectedProfile,
    selectModeWithValue,
    tablePayload,
  } = useBehaviorsPanelController({
    initialData,
    initialMode,
    initialFunnel,
    initialProperty,
  })

  const hasPropertiesTab = behaviourTabs.some((tab) => tab.value === "props")
  const hasFunnelsTab = behaviourTabs.some((tab) => tab.value === "funnels")
  const goalsAllZero =
    mode === "conversions" &&
    !!tablePayload &&
    tablePayload.results.length > 0 &&
    tablePayload.results.every(
      (item) => Number(item.uniques ?? 0) <= 0 && Number(item.total ?? 0) <= 0
    )
  const visitorsEmptyState =
    profilesSearch.trim().length > 0
      ? "No visitors match your search"
      : "No visitors found for this filter"

  return (
    <section className="flex flex-col gap-3 rounded-lg border border-border bg-card p-4">
      <header className="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-center sm:justify-between">
        <h2 className="text-base font-medium">{activeTitle}</h2>
        <PanelTabs>
          {behaviourTabs
            .filter((tab) => tab.value !== "funnels" && tab.value !== "props")
            .map((tab) => (
              <PanelTab
                key={tab.value}
                active={mode === tab.value}
                onClick={() => setAndStoreMode(tab.value)}
              >
                {tab.label}
              </PanelTab>
            ))}
          {hasPropertiesTab ? (
            propertyOptions.length > 0 ? (
              <SelectionTabDropdown
                active={mode === "props"}
                label="Properties"
                options={propertyOptions}
                value={activeProperty ?? undefined}
                searchPlaceholder="Search properties"
                onSelect={(value) => {
                  selectModeWithValue("props", value)
                }}
              />
            ) : (
              <PanelTab
                active={mode === "props"}
                onClick={() => setAndStoreMode("props")}
              >
                Properties
              </PanelTab>
            )
          ) : null}
          {hasFunnelsTab ? (
            <PanelTab
              active={mode === "funnels"}
              onClick={() => setAndStoreMode("funnels")}
            >
              Funnels
            </PanelTab>
          ) : null}
        </PanelTabs>
      </header>

      {mode === "conversions" && !tablePayload ? (
        <PanelEmptyState>
          <div className="text-center">
            <span className="font-medium text-foreground">
              No goals configured yet
            </span>
            <span className="mt-1 block">
              Open Analytics Settings &gt; Goals to add a managed goal or
              promote a detected custom event.
            </span>
          </div>
        </PanelEmptyState>
      ) : mode === "props" && !tablePayload ? (
        <PanelEmptyState>
          <div className="text-center">
            <span className="font-medium text-foreground">
              No custom properties configured
            </span>
            <span className="mt-1 block">
              Add a property in Analytics Settings to break down events here.
            </span>
          </div>
        </PanelEmptyState>
      ) : mode === "funnels" && !hasRenderableFunnels ? (
        <PanelEmptyState>
          <div className="text-center">
            <span className="font-medium text-foreground">
              No funnels configured yet
            </span>
            <span className="mt-1 block">
              Build a funnel in Analytics Settings to track step-by-step
              dropoff.
            </span>
          </div>
        </PanelEmptyState>
      ) : mode === "visitors" ? (
        <div className="space-y-4">
          <div className="flex items-center justify-end">
            <div className="relative w-full sm:max-w-xs">
              <Input
                placeholder="Search visitors"
                value={profilesSearch}
                onChange={(event) => setProfilesSearch(event.target.value)}
              />
            </div>
          </div>
          {loading ? (
            <PanelListSkeleton firstColumnLabel={firstColumnLabel} />
          ) : profilesData.results.length > 0 ? (
            <>
              <ProfilesList
                profiles={profilesData.results}
                onSelect={(profile) => {
                  setSelectedProfile(profile)
                  setJourneyOpen(true)
                }}
              />
              {profilesData.meta.hasMore ? (
                <div className="flex justify-center pt-2">
                  <button
                    type="button"
                    className="text-sm font-medium text-primary hover:text-primary/80 disabled:opacity-50"
                    disabled={profilesLoadingMore}
                    onClick={loadMoreProfiles}
                  >
                    {profilesLoadingMore ? "Loading…" : "Load more visitors"}
                  </button>
                </div>
              ) : null}
            </>
          ) : (
            <PanelEmptyState>
              <div className="text-center">
                <span className="font-medium text-foreground">
                  {visitorsEmptyState}
                </span>
                <span className="mt-1 block">
                  Try a different period, remove filters, or wait for more
                  traffic.
                </span>
              </div>
            </PanelEmptyState>
          )}
          <ProfileJourneySheet
            open={journeyOpen}
            onOpenChange={setJourneyOpen}
            profile={selectedProfile}
          />
        </div>
      ) : loading ? (
        <PanelListSkeleton firstColumnLabel={firstColumnLabel} />
      ) : goalsAllZero ? (
        <PanelEmptyState>
          <div className="text-center">
            <span className="font-medium text-foreground">
              No goals completed in this period
            </span>
            <span className="mt-1 block">
              Try a wider date range or remove filters to see historical goal
              performance.
            </span>
          </div>
        </PanelEmptyState>
      ) : hasRenderableFunnels && funnelData ? (
        <FunnelSteps
          data={funnelData}
          availableFunnels={availableFunnels}
          selectedFunnel={selectedFunnel}
          onSelectFunnel={(name: string) =>
            selectModeWithValue("funnels", name)
          }
        />
      ) : tablePayload ? (
        <>
          {mode === "props" && activeProperty ? (
            <p className="text-sm text-muted-foreground">
              Showing values for{" "}
              <span className="font-medium text-foreground">
                {activeProperty}
              </span>
            </p>
          ) : null}
          <MetricTable
            data={limitedTablePayload ?? tablePayload}
            highlightedMetric={
              mode === "conversions"
                ? "uniques"
                : tablePayload.metrics.includes("conversionRate")
                  ? "conversionRate"
                  : tablePayload.metrics[0]
            }
            onRowClick={handleRowClick}
            displayBars={false}
            revealSecondaryMetricsOnHover={false}
            firstColumnLabel={firstColumnLabel}
            barColorTheme="cyan"
          />
          <div className="mt-auto flex justify-center pt-3">
            <DetailsButton onClick={openDetailsDialog}>Details</DetailsButton>
          </div>
        </>
      ) : (
        <PanelEmptyState>
          <div className="text-center">
            <span className="font-medium text-foreground">
              No data available
            </span>
            <span className="mt-1 block">
              Try a different period or remove filters.
            </span>
          </div>
        </PanelEmptyState>
      )}

      {tablePayload && mode !== "visitors" ? (
        <RemoteDetailsDialog
          open={detailsOpen}
          onOpenChange={setDetailsDialogOpen}
          title={activeTitle}
          endpoint={analyticsScopedPath("/behaviors")}
          extras={{
            mode,
            funnel: selectedFunnel,
            property:
              mode === "props" ? (activeProperty ?? undefined) : undefined,
          }}
          firstColumnLabel={firstColumnLabel}
          initialSearch=""
          defaultSortKey={
            tablePayload.metrics.includes("conversionRate")
              ? ("conversionRate" as ListMetricKey)
              : (tablePayload.metrics[0] as ListMetricKey)
          }
          onRowClick={(item) => {
            handleRowClick(item)
            closeDetailsDialog()
          }}
        />
      ) : null}
    </section>
  )
}
