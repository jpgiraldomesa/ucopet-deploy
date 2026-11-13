create temp table equipo (usuario text, nombres text, apellidos text);
\copy equipo from '/tmp/seed/team.csv' with (format csv, delimiter ';', header true)

insert into persons (id, document_type, document_number, first_name, last_name, email, phone, address,
                     password_hash, is_admin, active, failed_attempts, token_version)
select md5('persona:' || usuario)::uuid, 'CC', (1010000000 + row_number() over (order by usuario))::text,
       nombres, apellidos, usuario || '@ucopet.com', null, null,
       :'clave', true, true, 0, 0
from equipo
on conflict do nothing;

insert into persons (id, document_type, document_number, first_name, last_name, email, phone, address,
                     password_hash, is_admin, active, failed_attempts, token_version)
values
  (md5('persona:medica.demo')::uuid, 'CC', '1020000001', 'Laura', 'Gómez Restrepo', 'medica@ucopet.com',
   '3001234567', 'Rionegro, Antioquia', :'clave', false, true, 0, 0),
  (md5('persona:medico.demo')::uuid, 'CC', '1020000002', 'Andrés', 'Rojas Henao', 'medico@ucopet.com',
   '3007654321', 'La Ceja, Antioquia', :'clave', false, true, 0, 0)
on conflict do nothing;

alter table doctors add column if not exists headquarter_id uuid;
update doctors set headquarter_id = case id when md5('medico:medico.demo')::uuid then md5('sede:laceja')::uuid
                                           else md5('sede:rionegro')::uuid end
where headquarter_id is null;

insert into doctors (id, id_person, license_number, headquarter_id) values
  (md5('medico:medica.demo')::uuid, md5('persona:medica.demo')::uuid, 'MV-ANT-10234', md5('sede:rionegro')::uuid),
  (md5('medico:medico.demo')::uuid, md5('persona:medico.demo')::uuid, 'MV-ANT-11872', md5('sede:laceja')::uuid)
on conflict do nothing;

alter table doctors alter column headquarter_id set not null;
