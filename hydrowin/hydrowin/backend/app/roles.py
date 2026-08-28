"""Роли пользователей организации.

- org_admin — администратор организации (платформа / производитель / завод)
- driver — водитель завода: видит только свою машину
- dispatcher — legacy, только для старых данных (чтение)

Ограничения дополнительно зависят от типа организации
(platform / manufacturer / client).
"""

ROLE_ORG_ADMIN = "org_admin"
ROLE_DRIVER = "driver"
ROLE_DISPATCHER = "dispatcher"

ADMIN_ROLES = (ROLE_ORG_ADMIN,)
# Водитель входит в staff: может логиниться и читать свой парк (1 машина).
STAFF_ROLES = (ROLE_ORG_ADMIN, ROLE_DISPATCHER, ROLE_DRIVER)

CREATABLE_ROLES = (ROLE_ORG_ADMIN, ROLE_DRIVER)
