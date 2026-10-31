insert into products (id, name, description, image_url, price, tax_category, sellable, active, category)
select md5('producto:' || name)::uuid, name, description, null, price, tax, true, true, category
from (values
  ('Vacuna antirrábica canina y felina', 'Dosis única de 1 ml. Refuerzo anual.', 38000, 'REDUCED', 'VACCINE'),
  ('Vacuna múltiple canina DHPPi+L', 'Moquillo, hepatitis, parvovirus, parainfluenza y leptospira. Dosis de 1 ml.', 62000, 'REDUCED', 'VACCINE'),
  ('Vacuna triple felina', 'Rinotraqueítis, calicivirus y panleucopenia. Dosis de 1 ml.', 58000, 'REDUCED', 'VACCINE'),
  ('Vacuna de tos de las perreras', 'Bordetella bronchiseptica, aplicación intranasal.', 55000, 'REDUCED', 'VACCINE'),
  ('NexGard 10,1 a 25 kg', 'Afoxolaner masticable contra pulgas y garrapatas. Una tableta al mes.', 72000, 'REDUCED', 'MEDICATION'),
  ('Bravecto 10 a 20 kg', 'Fluralaner masticable. Protección por 12 semanas.', 135000, 'REDUCED', 'MEDICATION'),
  ('Simparica 10 a 20 kg', 'Sarolaner masticable. Una tableta al mes.', 68000, 'REDUCED', 'MEDICATION'),
  ('Drontal Plus perro 10 kg', 'Antiparasitario interno de amplio espectro. Una tableta.', 21000, 'REDUCED', 'MEDICATION'),
  ('Revolution gato 2,6 a 7,5 kg', 'Selamectina en pipeta. Pulgas, ácaros y parásitos internos.', 64000, 'REDUCED', 'MEDICATION'),
  ('Meloxicam suspensión oral 1,5 mg/ml', 'Antiinflamatorio. Frasco de 10 ml.', 42000, 'REDUCED', 'MEDICATION'),
  ('Amoxicilina con ácido clavulánico 250 mg', 'Antibiótico. Caja por 10 tabletas.', 48000, 'REDUCED', 'MEDICATION'),
  ('Cefalexina 500 mg', 'Antibiótico. Caja por 10 cápsulas.', 32000, 'REDUCED', 'MEDICATION'),
  ('Prednisolona 5 mg', 'Corticoide. Caja por 20 tabletas.', 18000, 'REDUCED', 'MEDICATION'),
  ('Metronidazol 250 mg', 'Antiprotozoario. Caja por 20 tabletas.', 16000, 'REDUCED', 'MEDICATION'),
  ('Omeprazol 20 mg', 'Protector gástrico. Caja por 14 cápsulas.', 14000, 'REDUCED', 'MEDICATION'),
  ('Royal Canin Medium Adult 15 kg', 'Alimento seco para perros adultos de 11 a 25 kg.', 389000, 'EXEMPT', 'FOOD'),
  ('Hill''s Prescription Diet i/d canino 3,85 kg', 'Dieta veterinaria para el cuidado digestivo.', 215000, 'EXEMPT', 'FOOD'),
  ('Pro Plan gato adulto 3 kg', 'Alimento seco para gatos adultos.', 118000, 'EXEMPT', 'FOOD'),
  ('Lata de recuperación a/d 156 g', 'Dieta húmeda para convalecencia de perros y gatos.', 19500, 'EXEMPT', 'FOOD'),
  ('Collar isabelino talla M', 'Collar de protección posquirúrgica.', 22000, 'STANDARD', 'ACCESSORY'),
  ('Guacal para transporte mediano', 'Hasta 12 kg. Con puerta metálica.', 145000, 'STANDARD', 'ACCESSORY'),
  ('Correa retráctil 5 m', 'Para perros de hasta 25 kg.', 54000, 'STANDARD', 'ACCESSORY'),
  ('Shampoo de clorhexidina al 2 % 250 ml', 'Uso dermatológico.', 36000, 'STANDARD', 'HYGIENE'),
  ('Arena aglomerante para gatos 10 kg', 'Arena de bentonita sin aroma.', 39000, 'STANDARD', 'HYGIENE'),
  ('Limpiador ótico 120 ml', 'Limpieza del conducto auditivo.', 31000, 'STANDARD', 'HYGIENE'),
  ('Jeringa desechable 3 ml', 'Caja por 100 unidades.', 38000, 'STANDARD', 'SUPPLY'),
  ('Guantes de nitrilo talla M', 'Caja por 100 unidades.', 32000, 'STANDARD', 'SUPPLY'),
  ('Gasa estéril 7,5 x 7,5 cm', 'Paquete por 100 unidades.', 24000, 'STANDARD', 'SUPPLY'),
  ('Lactato de Ringer 500 ml', 'Solución para fluidoterapia.', 9500, 'STANDARD', 'SUPPLY'),
  ('Catéter intravenoso 22G', 'Caja por 50 unidades.', 85000, 'STANDARD', 'SUPPLY'),
  ('Sutura absorbible 3-0', 'Sobre por una unidad con aguja.', 21000, 'STANDARD', 'SUPPLY')
) as p(name, description, price, tax, category)
on conflict do nothing;

insert into services (id, name, description, image_url, price, tax_category, sellable, active, category, purchasable)
select md5('servicio:' || name)::uuid, name, description, null, price, tax, true, true, category, false
from (values
  ('Consulta general', 'Examen clínico completo con historia y plan de manejo.', 60000, 'EXEMPT', 'CONSULTATION'),
  ('Consulta de urgencias', 'Atención prioritaria sin cita.', 95000, 'EXEMPT', 'CONSULTATION'),
  ('Consulta de dermatología', 'Valoración por especialista, con raspado si hace falta.', 110000, 'EXEMPT', 'CONSULTATION'),
  ('Control posquirúrgico', 'Revisión de herida y retiro de puntos.', 35000, 'EXEMPT', 'CONSULTATION'),
  ('Aplicación de vacuna', 'Aplicación y registro en el carné. La vacuna se cobra aparte.', 15000, 'EXEMPT', 'VACCINATION'),
  ('Esterilización de hembra canina', 'Ovariohisterectomía con anestesia inhalada.', 450000, 'EXEMPT', 'SURGERY'),
  ('Castración de felino macho', 'Orquiectomía con anestesia.', 180000, 'EXEMPT', 'SURGERY'),
  ('Profilaxis dental', 'Limpieza con ultrasonido bajo anestesia.', 320000, 'EXEMPT', 'SURGERY'),
  ('Hemograma completo', 'Cuadro hemático con frotis.', 45000, 'EXEMPT', 'LABORATORY'),
  ('Química sanguínea básica', 'ALT, creatinina, BUN y glucosa.', 85000, 'EXEMPT', 'LABORATORY'),
  ('Coprológico', 'Examen de materia fecal.', 30000, 'EXEMPT', 'LABORATORY'),
  ('Ecografía abdominal', 'Estudio ecográfico con informe.', 150000, 'EXEMPT', 'LABORATORY'),
  ('Hospitalización por día', 'Incluye monitoreo y fluidoterapia. Medicamentos aparte.', 180000, 'EXEMPT', 'HOSPITALIZATION'),
  ('Baño y peluquería perro mediano', 'Baño, secado, corte y limpieza de oídos.', 65000, 'STANDARD', 'GROOMING'),
  ('Corte de uñas', 'Sin cita.', 15000, 'STANDARD', 'GROOMING'),
  ('Implantación de microchip', 'Microchip ISO con registro.', 70000, 'EXEMPT', 'GENERAL')
) as s(name, description, price, tax, category)
on conflict do nothing;

insert into service_headquarters (id, service_id, headquarter_id)
select md5('servicio-sede:' || s.id || h.id)::uuid, s.id, h.id
from services s
join headquarter h on h.id in (md5('sede:rionegro')::uuid, md5('sede:laceja')::uuid, md5('sede:marinilla')::uuid, md5('sede:elretiro')::uuid)
where s.id = md5('servicio:' || s.name)::uuid
  and (h.id = md5('sede:rionegro')::uuid
       or s.category not in ('SURGERY', 'HOSPITALIZATION')
          and s.name <> 'Ecografía abdominal')
on conflict do nothing;

insert into stocks (id, product_id, headquarter_id, quantity)
select md5('stock:' || p.id || h.id)::uuid, p.id, h.id,
       case when abs(hashtext(p.name || h.name)) % 9 = 0 then abs(hashtext(h.name || p.name)) % 5
            else 6 + abs(hashtext(p.name || h.name)) % 40 end
from products p
join headquarter h on h.id in (md5('sede:rionegro')::uuid, md5('sede:laceja')::uuid, md5('sede:marinilla')::uuid, md5('sede:elretiro')::uuid)
where p.id = md5('producto:' || p.name)::uuid
on conflict do nothing;

insert into stock_movements (id, product_id, headquarter_id, quantity, balance_after, reason, note, occurred_at, performed_by)
select md5('movimiento-apertura:' || st.id)::uuid, st.product_id, st.headquarter_id, st.quantity, st.quantity,
       'OPENING', 'Saldo inicial de la semilla', now(), null
from stocks st
where st.id = md5('stock:' || st.product_id || st.headquarter_id)::uuid
on conflict do nothing;
