export type WorkOrderDrawing = {
  code: string;
  title: string;
  revision: string;
  src: string;
  alt: string;
  width: number;
  height: number;
};

export const FW001_RS01_LOADING_DOCK = {
  sourcePixel: { x: 246, y: 255 },
  normalized: { x: 23.077, y: 37.39 },
  acceptanceRegion: { minX: 230, maxX: 262, minY: 238, maxY: 270 },
  excludedParkingCanopyRegion: { minX: 200, maxX: 430, minY: 300, maxY: 390 },
} as const;

export const WORK_ORDER_DRAWINGS: readonly WorkOrderDrawing[] = [
  {
    code: "FW-001",
    title: "Site Plot Plan, Perspective, 1st Storey and Utility Block Layout",
    revision: "A (25 May 2024)",
    src: "/work-order-drawings/FW-001.png",
    alt: "FW-001 Site Plot Plan, Perspective, 1st Storey and Utility Block Layout",
    width: 1066,
    height: 682,
  },
  {
    code: "FW-002",
    title: "2nd Storey Plan",
    revision: "A (28 Jul 2026)",
    src: "/work-order-drawings/FW-002.png",
    alt: "FW-002 2nd Storey Plan",
    width: 1024,
    height: 742,
  },
  {
    code: "FW-003",
    title: "Roof Plan",
    revision: "A (28 Jul 2026)",
    src: "/work-order-drawings/FW-003.png",
    alt: "FW-003 Roof Plan",
    width: 1024,
    height: 742,
  },
  {
    code: "FW-004",
    title: "North, South, East and West Elevations",
    revision: "A (28 Jul 2026)",
    src: "/work-order-drawings/FW-004.png",
    alt: "FW-004 North, South, East and West Elevations",
    width: 1024,
    height: 742,
  },
];
