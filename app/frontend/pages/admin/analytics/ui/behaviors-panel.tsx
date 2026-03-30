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
    showNoGoalsHint,
    tablePayload,
  } = useBehaviorsPanelController({
    initialData,
    initialMode,
    initialFunnel,
    initialProperty,
  })

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
          {propertyOptions.length > 0 ? (
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
          )}
          {availableFunnels.length > 0 ? (
            <SelectionTabDropdown
              active={mode === "funnels"}
              label="Funnels"
              options={availableFunnels}
              value={selectedFunnel}
              searchPlaceholder="Search funnels"
              onSelect={(value) => {
                selectModeWithValue("funnels", value)
              }}
            />
          ) : (
            <PanelTab
              active={mode === "funnels"}
              onClick={() => setAndStoreMode("funnels")}
            >
              Funnels
            </PanelTab>
          )}
        </PanelTabs>
      </header>

      {showNoGoalsHint ? (
        <p className="text-sm text-muted-foreground">
          No goals configured yet. Explore properties or funnels in the
          meantime.
        </p>
      ) : null}

      {mode === "visitors" ? (
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
            <PanelEmptyState>No visitors found for this filter</PanelEmptyState>
          )}
          <ProfileJourneySheet
            open={journeyOpen}
            onOpenChange={setJourneyOpen}
            profile={selectedProfile}
          />
        </div>
      ) : loading ? (
        <PanelListSkeleton firstColumnLabel={firstColumnLabel} />
      ) : hasRenderableFunnels && funnelData ? (
        <FunnelSteps data={funnelData} />
      ) : mode === "funnels" ? (
        <p className="text-sm text-muted-foreground">No funnels available</p>
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
        <PanelEmptyState>No data available</PanelEmptyState>
      )}

      {tablePayload ? (
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
