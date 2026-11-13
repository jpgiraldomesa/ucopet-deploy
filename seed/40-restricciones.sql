alter table if exists notifications drop constraint if exists notifications_type_check;
alter table if exists notifications add constraint notifications_type_check check (type in (
  'APPOINTMENT_CREATED', 'ORDER_AUTHORIZED', 'ORDER_REJECTED', 'ORDER_PENDING', 'LOGIN_SUCCEDED',
  'PET_CREATED', 'PET_UPDATED', 'PET_DELETED', 'DOCTOR_CREATED', 'DOCTOR_UPDATED', 'DOCTOR_DELETED',
  'TUTOR_CREATED', 'TUTOR_UPDATED', 'TUTOR_DELETED', 'USER_CREATED', 'USER_UPDATED', 'USER_DELETED'));

alter table if exists providers drop constraint if exists providers_id_type_check;
alter table if exists providers add constraint providers_id_type_check check (id_type in (
  'CC', 'TI', 'CE', 'PA', 'RC', 'PPT', 'NIT'));
