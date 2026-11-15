# Multi-Branch Cooperative Bank Management System

DBIS Lab (CS257) project. A relational database system for a multi-branch cooperative bank, covering customer and account management, branch and employee management, atomic and concurrency-safe transaction processing, a loan lifecycle with guarantors and EMI schedules, and reporting.

Problem statement: https://drive.google.com/file/d/1O-rlJTe_RvUfFdJQnFa5k7VxSm0PuZpK/view?usp=drive_link

## Requirements

MySQL 8.0.16 or later (CHECK constraints are enforced from this version).

## Building the database

From the repository root:

    ./scripts/reset_db.sh      # drops and recreates the CooperativeBank database
    ./scripts/run_all.sh       # runs database/01 to 07 in numeric order

Set MYSQL_USER, MYSQL_PASSWORD (optional) and MYSQL_HOST (optional) in the environment, or edit the variables at the top of each script.

## Repository layout

    docs/                    Proposal, problem statement, ER diagram, UML, normalization, report
    database/                Numbered SQL files, executed in order
      01_schema.sql            Tables and base constraints
      02_constraints_triggers.sql   Additional constraints and triggers
      03_seed_data.sql         Demonstration dataset
      04_transactions.sql      Deposit, withdrawal, transfer procedures
      05_loans.sql             Loan application, approval, disbursal, EMI, repayment
      06_views.sql             Reporting views
      07_indexes.sql           Indexes (kept separate for before/after comparison)
    experiments/             Self-contained experiments, not part of the core build
      concurrency/             Lost-update anomaly and its resolution
      indexing/                Bulk data generator and timing comparison
      query_optimization/      Slow queries, rewrites and EXPLAIN output
    scripts/                 Helper scripts to reset and build the database
    tests/                   Smoke tests (balance reconciliation, constraint checks)

## Team

Eklavya (250001028), Tanush Bansal (250001071), Chetan Yogbharti (250001023), Parth Kalia (250001054)
