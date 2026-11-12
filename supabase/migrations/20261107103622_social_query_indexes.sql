create index forum_threads_author on private.forum_threads(author_id);
create index forum_threads_clan on private.forum_threads(clan_id);
create index conversations_planet on private.conversations(planet_id);
create index conversations_season on private.conversations(season_id);
create index economy_ledger_empire_sequence on private.economy_ledger(empire_id,id desc);
