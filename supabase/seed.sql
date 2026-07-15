-- Categories
INSERT INTO categories (name)
VALUES
('Lighting'),
('Electrical'),
('Air Conditioning'),
('Plumbing'),
('Carpentry'),
('Painting'),
('Cleaning'),
('Flooring'),
('Ceiling'),
('Doors'),
('Lift'),
('Fire Protection'),
('Security'),
('Network'),
('General Maintenance')
ON CONFLICT (name) DO NOTHING;