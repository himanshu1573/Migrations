-- Add the exception column to vendor_master
-- If true, the vendor can login with password even if they are an internal recruiter
ALTER TABLE public.vendor_master 
ADD COLUMN IF NOT EXISTS vendor_microsoft_mail_exception BOOLEAN DEFAULT false;

-- Create an index to speed up the check-vendor query
CREATE INDEX IF NOT EXISTS idx_vendor_master_mail_exception 
ON public.vendor_master (vendor_microsoft_mail_exception);

COMMENT ON COLUMN public.vendor_master.vendor_microsoft_mail_exception 
IS 'When true, allows the vendor to bypass Microsoft SSO requirements and login via password.';
