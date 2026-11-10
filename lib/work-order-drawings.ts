export type WorkOrderDrawing = {
  code: string;
  title: string;
  revision: string;
  src: string;
  alt: string;
  width: number;
  height: number;
};

/** Measured on FW-001 Rev A (1066 x 682 px, 25 May 2024). Rev B (10 Nov 2026) re-places the LDB-01 pin by script. */
export const FW001_REV_A_SIZE = { width: 1066, height: 682 } as const;

export const FW001_RS01_LOADING_DOCK = {
  sourcePixel: { x: 246, y: 255 },
  normalized: { x: 23.077, y: 37.39 },
  acceptanceRegion: { minX: 230, maxX: 262, minY: 238, maxY: 270 },
  excludedParkingCanopyRegion: { minX: 200, maxX: 430, minY: 300, maxY: 390 },
} as const;

export const WORK_ORDER_DRAWINGS: readonly WorkOrderDrawing[] = [
  {
    code: "FW-001",
    // D-47 Rev B (10 Nov 2026): one building (Main Building, Central Plant Block, Utility Block), drawn to scale.
    title: "Site Plot Plan and 1st Storey Layout (one building)",
    revision: "B (10 Nov 2026)",
    src: "/work-order-drawings/FW-001-rev-b.png",
    alt: "FW-001 Site Plot Plan and 1st Storey Layout of the one building",
    width: 2048,
    height: 1484,
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
    // D-47 Rev B (10 Nov 2026): elevations of the one building, to scale.
    title: "North, South, East and West Elevations (one building)",
    revision: "B (10 Nov 2026)",
    src: "/work-order-drawings/FW-004-rev-b.png",
    alt: "FW-004 North, South, East and West Elevations of the one building",
    width: 2048,
    height: 1484,
  },
  // Owner, 10 Nov 2026: the new drawings are shown on the Work Order page too.
  {
    code: "FW-005",
    title: "3D Perspective and Utility Block Layout Plan (one building)",
    revision: "B (10 Nov 2026)",
    src: "/work-order-drawings/FW-005-rev-b.png",
    alt: "FW-005 3D perspective of the one building and the Utility Block layout plan",
    width: 2048,
    height: 1484,
  },
  // D-47 (10 Nov 2026): the Central Plant Block between the Main Building and the Utility Block.
  {
    code: "FW-006",
    title: "Central Plant Block Layout and Roof Plan (AHU Room, Chiller Plant Room)",
    revision: "A (10 Nov 2026)",
    src: "/work-order-drawings/FW-006.png",
    alt: "FW-006 Central Plant Block Layout and Roof Plan",
    width: 2048,
    height: 1484,
  },
  // D-48 (10 Nov 2026): maintenance access on the car park solar PV canopy.
  {
    code: "FW-007",
    title: "Car Park Solar PV Canopy: Maintenance Access Plan and Section",
    revision: "A (10 Nov 2026)",
    src: "/work-order-drawings/FW-007.png",
    alt: "FW-007 Car Park Solar PV Canopy maintenance access plan and section",
    width: 2048,
    height: 1484,
  },
  {
    code: "FW-008",
    title: "Rendered Site Plan (presentation, to scale)",
    revision: "A (10 Nov 2026)",
    src: "/work-order-drawings/FW-008-rendered-site-plan.jpg",
    alt: "FW-008 rendered site plan of the one building, car park canopy and site",
    width: 2800,
    height: 1980,
  },
];
