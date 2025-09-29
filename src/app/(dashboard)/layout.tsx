import { SidebarProvider, SidebarTrigger } from "@/components/ui/sidebar";
import { AppSidebar } from "@/components/app-sidebar";
import { UserButton } from "@clerk/nextjs";
import { cookies } from "next/headers";

export default async function Layout({
  children,
}: {
  children: React.ReactNode;
}) {
  const cookieStore = await cookies();
  const defaultOpen = cookieStore.get("sidebar_state")?.value === "true";

  return (
    <SidebarProvider defaultOpen={defaultOpen}>
      <AppSidebar />
      <main className="flex min-h-screen flex-1 flex-col">
        <header className="sticky top-0 z-50 flex h-16 items-center justify-between border-b bg-background px-3">
          <SidebarTrigger className="-ml-1" />
          <UserButton />
        </header>
        <div className="flex-1 p-3">{children}</div>
      </main>
    </SidebarProvider>
  );
}
