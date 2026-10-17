import { createFileRoute } from "@tanstack/react-router";
import { createServerFn } from "@tanstack/react-start";
import { LatentStudio } from "@/components/latent-studio";

const openingMark = createServerFn({ method: "GET" }).handler(async () => {
  const { openingDataUrl } = await import("@/lib/qr/png.server");
  return openingDataUrl();
});

export const Route = createFileRoute("/")({
  loader: () => openingMark(),
  component: Home,
});

function Home() {
  const openingSrc = Route.useLoaderData();
  return <LatentStudio openingSrc={openingSrc} />;
}
