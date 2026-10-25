"use client";

import { useParams } from "next/navigation";
import type { ReactNode } from "react";
import { Shell } from "@/components/shell";

export default function SpaceLayout({ children }: { children: ReactNode }) {
  const params = useParams<{ spaceId: string }>();
  return <Shell spaceId={params.spaceId}>{children}</Shell>;
}
