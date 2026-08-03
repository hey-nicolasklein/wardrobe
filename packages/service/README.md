# `@form/service`

This package is the durable infrastructure boundary shared by the API and worker. It owns ordered PostgreSQL migrations, tenant-scoped private object storage, leased remote-image jobs, dependency health, and deterministic fixture reset.

The package deliberately does not own authentication, wardrobe lifecycle rules, or GPT providers. Those modules build on these primitives in later Wayfinder tickets.

For local commands, copy `.env.example` to `.env.local`, start the root development services, and run the root migration or fixture script.
