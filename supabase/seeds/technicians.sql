-- ===========================================
-- Seed Technicians
-- ===========================================

INSERT INTO technicians
(
    id,
    name,
    email,
    phone,
    trade
)
VALUES
(
    'd1000000-0000-0000-0000-000000000001',
    'Yeo Eng Chian',
    'koi.kpr@gmail.com',
    '+65 9155 5690',
    'Lighting'
),
(
    'd1000000-0000-0000-0000-000000000002',
    'Michael Teo',
    'michael.teo@example.com',
    '+65 9123 4567',
    'Electrical'
),
(
    'd1000000-0000-0000-0000-000000000003',
    'Teo Khiang Kok',
    'kk.teo@example.com',
    '+65 9234 5678',
    'Air Conditioning'
),
(
    'd1000000-0000-0000-0000-000000000004',
    'Martin Kok',
    'martin.kok@example.com',
    '+65 9345 6789',
    'Plumbing'
),
(
    'd1000000-0000-0000-0000-000000000005',
    'Augustine Loh',
    'augustine.loh@example.com',
    '+65 9456 7890',
    'Carpentry'
),
(
    'd1000000-0000-0000-0000-000000000006',
    'Selene See',
    'selene.see@example.com',
    '+65 9567 8901',
    'Painting'
),
(
    'd1000000-0000-0000-0000-000000000007',
    'Maria Boey',
    'maria.boey@example.com',
    '+65 9678 9012',
    'Cleaning'
),
(
    'd1000000-0000-0000-0000-000000000008',
    'Paul Lim',
    'paul.lim@example.com',
    '+65 9789 0123',
    'Doors'
),
(
    'd1000000-0000-0000-0000-000000000009',
    'Venkat Dana',
    'venkat.dana@example.com',
    '+65 9890 1234',
    'Lift'
),
(
    'd1000000-0000-0000-0000-000000000010',
    'Jasmine Joo',
    'jasmine.joo@example.com',
    '+65 9001 2345',
    'Fire Protection'
),
(
    'd1000000-0000-0000-0000-000000000011',
    'Foo Keng Hee',
    'kenghee.foo@example.com',
    '+65 9112 3456',
    'Cleaning'
),
(
    'd1000000-0000-0000-0000-000000000012',
    'Ethan Chua',
    'ethan.chua@example.com',
    '+65 9223 4567',
    'Security'
),
(
    'd1000000-0000-0000-0000-000000000013',
    'William Chan',
    'william.chan@example.com',
    '+65 9334 5678',
    'Network'
),
(
    'd1000000-0000-0000-0000-000000000014',
    'Sridhar',
    'sridhar@example.com',
    '+65 9445 6789',
    'General Maintenance'
)
ON CONFLICT (id) DO NOTHING;