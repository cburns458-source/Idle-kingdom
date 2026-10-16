-- Guild achievement helpers and banner palette. Run against a project that
-- has 20261016170000_guild_achievements_and_banner.

\pset pager off

do $$
begin
  if public.guild_hall_tier_material_cost('build_the_hall') <> 1100 then
    raise exception 'build the hall materials should be 1100';
  end if;
  if public.guild_hall_materials_spent('["build_the_hall"]'::jsonb) <> 1100 then
    raise exception 'spent materials should follow completed tiers';
  end if;
  if public.guild_donor_count(
       '{"a":10,"b":0}'::jsonb,
       '{"b":true,"c":true}'::jsonb
     ) <> 3 then
    raise exception 'donor count should union gold and material donors';
  end if;
  if public.guild_banner_normalized(
       '00000000-0000-0000-0000-000000000001',
       '{"background":"slate","accent":"ivory"}'::jsonb
     ) ->> 'background' is distinct from 'slate' then
    raise exception 'default banner colours should normalise';
  end if;
  begin
    perform public.guild_banner_normalized(
      '00000000-0000-0000-0000-000000000001',
      '{"background":"gold","accent":"ivory"}'::jsonb
    );
    raise exception 'gold is not on the banner palette';
  exception
    when others then
      if sqlerrm not like 'That colour is not on the banner palette.' then
        raise;
      end if;
  end;
end $$;
