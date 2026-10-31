insert into headquarter (id, name, address, is_active) values
  (md5('sede:rionegro')::uuid,  'UcoPet Rionegro',  'Calle 49 # 51-30, Rionegro, Antioquia', true),
  (md5('sede:laceja')::uuid,    'UcoPet La Ceja',   'Carrera 20 # 19-45, La Ceja, Antioquia', true),
  (md5('sede:marinilla')::uuid, 'UcoPet Marinilla', 'Calle 30 # 29-12, Marinilla, Antioquia', true),
  (md5('sede:elretiro')::uuid,  'UcoPet El Retiro', 'Carrera 21 # 20-08, El Retiro, Antioquia', true)
on conflict do nothing;
