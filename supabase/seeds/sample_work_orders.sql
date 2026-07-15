-- ===========================================
-- Sample Work Orders
-- ===========================================

-- Lighting
INSERT INTO work_orders
(
    title,
    description,
    category_id,
    priority,
    status,
    location
)
VALUES
(
    'c1000000-0000-0000-0000-000000000001',
    'Linear Light in Director Room is very dim',
    'The linear light is very dim and the room cannot be used safely.',
    (
        SELECT id
        FROM categories
        WHERE name = 'Lighting'
        LIMIT 1
    ),
    'critical',
    'submitted',
    'SDD Office - Quiet Room'
)
ON CONFLICT (id) DO NOTHING;

-- Plumbing
INSERT INTO work_orders
(
    title,
    description,
    category_id,
    priority,
    status,
    location
)
VALUES
(
    'c1000000-0000-0000-0000-000000000002',
    'Water leaking under pantry sink',
    'Continuous water leak causing the pantry floor to become slippery.',
    (
        SELECT id
        FROM categories
        WHERE name = 'Plumbing'
        LIMIT 1
    ),
    'high',
    'approved',
    'Pantry'
)
ON CONFLICT (id) DO NOTHING;

-- Air Conditioning
INSERT INTO work_orders
(
    title,
    description,
    category_id,
    priority,
    status,
    location
)
VALUES
(
    'c1000000-0000-0000-0000-000000000003',
    'Meeting Room Air Conditioning not cooling',
    'Temperature remains above 29°C during meetings.',
    (
        SELECT id
        FROM categories
        WHERE name = 'Air Conditioning'
        LIMIT 1
    ),
    'high',
    'in_progress',
    'Meeting Room 1'
)
ON CONFLICT (id) DO NOTHING;

-- Cleaning
INSERT INTO work_orders
(
    title,
    description,
    category_id,
    priority,
    status,
    location
)
VALUES
(
    'c1000000-0000-0000-0000-000000000004',
    'Deep cleaning required after renovation',
    'Dust and debris remain after renovation works.',
    (
        SELECT id
        FROM categories
        WHERE name = 'Cleaning'
        LIMIT 1
    ),
    'medium',
    'done',
    'Training Room'
)
ON CONFLICT (id) DO NOTHING;