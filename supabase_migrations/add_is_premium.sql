-- Zone Premium: flag en perfil de usuario (activar tras compra verificada en backend).
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS is_premium BOOLEAN NOT NULL DEFAULT FALSE;
