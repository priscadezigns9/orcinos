# Presab data foundation

`schema.sql` defines the production data model for Presab while the current interface remains a controlled demo.

It covers:

- schools and staff profiles
- classes, teacher assignments, and student enrollment
- parent email contacts and consent
- manual, camera, and imported attendance records
- attendance corrections and audit history
- email notification queue and delivery status

The schema is intentionally not connected to the public demo yet. Authentication and Row Level Security will be added as the final project phase, as planned. Until then, the manual interface continues using synthetic browser data.
