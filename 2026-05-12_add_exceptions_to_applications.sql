-- Migration: Add exceptions column to applications_id table
ALTER TABLE public.applications_id ADD COLUMN exceptions text;
