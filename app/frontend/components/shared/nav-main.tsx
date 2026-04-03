import { Link, usePage } from "@inertiajs/react"
import { ChevronRight, type LucideIcon } from "lucide-react"

import type { ShellLinkPrefetchProps } from "@/lib/shell-prefetch"
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible"
import {
  SidebarGroup,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarMenuSub,
  SidebarMenuSubButton,
  SidebarMenuSubItem,
} from "@/components/ui/sidebar"

export interface NavItem {
  title: string
  url: string
  icon?: LucideIcon
  isActive?: boolean
  external?: boolean
  items?: { title: string; url: string }[]
}

function normalizePath(currentUrl: string): string {
  return currentUrl.split("?")[0].split("#")[0]
}

function isPathMatch(path: string, url: string): boolean {
  return path === url || path.startsWith(url + "/")
}

function mostSpecificMatch<T extends { url: string }>(
  path: string,
  items: T[]
): string | null {
  const matches = items
    .map((item) => item.url)
    .filter((url) => url !== "#" && isPathMatch(path, url))

  if (matches.length === 0) return null

  return matches.sort((left, right) => right.length - left.length)[0]
}

function isActive(url: string, activeUrl: string | null): boolean {
  return activeUrl === url
}

function isGroupActive(path: string, item: NavItem): boolean {
  if (item.url !== "#" && isPathMatch(path, item.url)) return true

  if (item.items?.length) {
    return mostSpecificMatch(path, item.items) !== null
  }

  return false
}

export function NavMain({
  label,
  items,
  linkPropsForUrl,
}: {
  label?: string
  items: NavItem[]
  linkPropsForUrl?: (url: string) => Partial<ShellLinkPrefetchProps>
}) {
  const { url: currentUrl } = usePage()
  const path = normalizePath(currentUrl)
  const activeItemUrl = mostSpecificMatch(
    path,
    items.filter((item) => !item.items?.length)
  )

  return (
    <SidebarGroup>
      {label && <SidebarGroupLabel>{label}</SidebarGroupLabel>}
      <SidebarMenu>
        {items.map((item) =>
          item.items && item.items.length > 0 ? (
            <Collapsible
              key={item.title}
              defaultOpen={item.isActive || isGroupActive(path, item)}
              className="group/collapsible"
            >
              <SidebarMenuItem>
                <CollapsibleTrigger
                  render={<SidebarMenuButton tooltip={item.title} />}
                >
                  {item.icon && <item.icon />}
                  <span>{item.title}</span>
                  <ChevronRight className="ml-auto transition-transform duration-200 group-data-[state=open]/collapsible:rotate-90" />
                </CollapsibleTrigger>
                <CollapsibleContent>
                  <SidebarMenuSub>
                    {(() => {
                      const activeSubItemUrl = mostSpecificMatch(
                        path,
                        item.items
                      )

                      return item.items.map((subItem) => (
                        <SidebarMenuSubItem key={subItem.title}>
                          <SidebarMenuSubButton
                            render={
                              <Link
                                href={subItem.url}
                                {...(linkPropsForUrl?.(subItem.url) ?? {})}
                              />
                            }
                            isActive={isActive(subItem.url, activeSubItemUrl)}
                          >
                            <span>{subItem.title}</span>
                          </SidebarMenuSubButton>
                        </SidebarMenuSubItem>
                      ))
                    })()}
                  </SidebarMenuSub>
                </CollapsibleContent>
              </SidebarMenuItem>
            </Collapsible>
          ) : (
            <SidebarMenuItem key={item.title}>
              <SidebarMenuButton
                render={
                  item.external ? (
                    <a
                      href={item.url}
                      target="_blank"
                      rel="noopener noreferrer"
                    />
                  ) : (
                    <Link
                      href={item.url}
                      {...(linkPropsForUrl?.(item.url) ?? {})}
                    />
                  )
                }
                tooltip={item.title}
                isActive={item.isActive || isActive(item.url, activeItemUrl)}
              >
                {item.icon && <item.icon />}
                <span>{item.title}</span>
              </SidebarMenuButton>
            </SidebarMenuItem>
          )
        )}
      </SidebarMenu>
    </SidebarGroup>
  )
}
