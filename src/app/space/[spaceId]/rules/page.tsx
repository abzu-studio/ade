"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { WeightList } from "@/components/ade/weights";
import { PageHeader } from "@/components/ade/widgets";
import { ATTENDANCE_FORMULA } from "@/core/constants";
import { useI18n } from "@/i18n";

export default function RulesPage() {
  const { t } = useI18n();
  return (
    <>
      <PageHeader title={t("rules.title")} />
      <Card>
        <CardHeader>
          <CardTitle>{t("rules.attendanceTitle")}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          <p>{ATTENDANCE_FORMULA}</p>
          <p>{t("rules.attendanceBody")}</p>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("rules.volunteerTitle")}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          <p>{t("rules.volunteerBody")}</p>
          <WeightList />
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("rules.statesTitle")}</CardTitle>
        </CardHeader>
        <CardContent className="text-sm">{t("rules.statesBody")}</CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("rules.collabTitle")}</CardTitle>
        </CardHeader>
        <CardContent className="text-sm">{t("rules.collabBody")}</CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("rules.docsTitle")}</CardTitle>
        </CardHeader>
        <CardContent className="text-sm">{t("rules.docsBody")}</CardContent>
      </Card>
    </>
  );
}
