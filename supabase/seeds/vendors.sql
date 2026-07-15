-- ===========================================
-- Seed Vendors
-- Facility Works Monitor
-- ===========================================

CREATE TABLE IF NOT EXISTS vendors
(
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name TEXT NOT NULL UNIQUE,

    trade TEXT NOT NULL,

    contact_person TEXT,

    phone TEXT,

    email TEXT,

    address TEXT,

    active BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO vendors
(
    id,
    name,
    trade,
    contact_person,
    phone,
    email,
    address
)
VALUES

(
    'f1000000-0000-0000-0000-000000000001',
    'ABC Electrical Engineering Pte Ltd',
    'Electrical',
    'Michael Tan',
    '+65 6123 1001',
    'service@abcelectrical.com.sg',
    '1 Ubi Avenue 1, Singapore'
),

(
    'f1000000-0000-0000-0000-000000000002',
    'Hydro Plumbing Services Pte Ltd',
    'Plumbing',
    'David Lim',
    '+65 6123 1002',
    'support@hydroplumbing.com.sg',
    '10 Kallang Way, Singapore'
),

(
    'f1000000-0000-0000-0000-000000000003',
    'CoolAir Engineering Pte Ltd',
    'Air Conditioning',
    'Kelvin Ong',
    '+65 6123 1003',
    'service@coolair.com.sg',
    '25 Pioneer Road, Singapore'
),

(
    'f1000000-0000-0000-0000-000000000004',
    'LiftTech Singapore Pte Ltd',
    'Lift',
    'Steven Goh',
    '+65 6123 1004',
    'operations@lifttech.com.sg',
    '100 Jurong East Street 21'
),

(
    'f1000000-0000-0000-0000-000000000005',
    'SafeFire Engineering Pte Ltd',
    'Fire Protection',
    'Daniel Chua',
    '+65 6123 1005',
    'service@safefire.com.sg',
    '50 Woodlands Industrial Park'
),

(
    'f1000000-0000-0000-0000-000000000006',
    'Prime Cleaning Services Pte Ltd',
    'Cleaning',
    'Grace Lee',
    '+65 6123 1006',
    'support@primeclean.com.sg',
    '8 Toa Payoh Industrial Park'
),

(
    'f1000000-0000-0000-0000-000000000007',
    'SecureGuard Pte Ltd Pte Ltd',
    'Security',
    'Jason Koh',
    '+65 6123 1007',
    'ops@secureguard.com.sg',
    '18 Sin Ming Lane'
),

(
    'f1000000-0000-0000-0000-000000000008',
    'NetLink Solutions Pte Ltd',
    'Network',
    'Vincent Ho',
    '+65 6123 1008',
    'helpdesk@netlink.com.sg',
    '30 Changi Business Park'
)

ON CONFLICT (id) DO NOTHING;