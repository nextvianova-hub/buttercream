-- =====================================================
-- The Buttercream: update 2
--   1. Customers can check their order status
--   2. Telegram message when a new order arrives
-- Supabase > SQL Editor > paste all > Run
-- =====================================================

-- 1. Order status lookup (needs BOTH the order number and the phone number)
create or replace function public.order_status(p_order_no bigint, p_phone text)
returns table (order_no bigint, status text, needed_date date, total numeric, lines jsonb, created_at timestamptz)
language sql stable security definer
set search_path = public
as $$
  select o.order_no, o.status, o.needed_date, o.total, o.lines, o.created_at
  from public.orders o
  where o.order_no = p_order_no
    and length(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g')) >= 9
    and right(regexp_replace(o.phone, '\D', '', 'g'), 9)
      = right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 9);
$$;
revoke all on function public.order_status(bigint, text) from public;
grant execute on function public.order_status(bigint, text) to anon, authenticated;

-- 2. Telegram notification for every new order
create extension if not exists pg_net with schema extensions;

create or replace function public.notify_new_order()
returns trigger
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_token text;
  v_chats text;
  v_chat  text;
  v_text  text;
  v_line  jsonb;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name = 'telegram_bot_token';
  select decrypted_secret into v_chats from vault.decrypted_secrets where name = 'telegram_chat_ids';
  if v_token is null or v_chats is null then
    return new;  -- Telegram not set up yet
  end if;

  v_text := '🎂 අලුත් ඇණවුමක් #' || new.order_no || E'\n'
         || 'නම: ' || new.customer_name || E'\n'
         || 'දුරකථන: ' || new.phone || E'\n'
         || 'අවශ්‍ය දිනය: ' || new.needed_date || E'\n\n';
  for v_line in select * from jsonb_array_elements(new.lines) loop
    v_text := v_text || '• ' || (v_line->>'qty') || ' × ' || (v_line->>'name')
           || case when v_line->>'weight' is not null then ' (' || (v_line->>'weight') || ' kg)' else '' end
           || case when coalesce(v_line->>'message', '') <> '' then ' "' || (v_line->>'message') || '"' else '' end
           || E'\n';
  end loop;
  if coalesce(new.note, '') <> '' then
    v_text := v_text || E'\nසටහන: ' || new.note || E'\n';
  end if;
  v_text := v_text || E'\nමුළු මුදල: රු. ' || to_char(new.total, 'FM999,999,990');

  foreach v_chat in array string_to_array(v_chats, ',') loop
    if trim(v_chat) <> '' then
      perform net.http_post(
        url  := 'https://api.telegram.org/bot' || v_token || '/sendMessage',
        body := jsonb_build_object('chat_id', trim(v_chat), 'text', v_text)
      );
    end if;
  end loop;
  return new;
exception when others then
  return new;  -- a notification problem must never block an order
end;
$$;
revoke all on function public.notify_new_order() from public, anon, authenticated;

drop trigger if exists orders_notify on public.orders;
create trigger orders_notify
  after insert on public.orders
  for each row execute function public.notify_new_order();
