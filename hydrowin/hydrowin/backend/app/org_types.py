"""Типы организаций и доступ к машинам."""

# platform → manufacturer → client (завод)
ORG_TYPE_PLATFORM = "platform"
ORG_TYPE_MANUFACTURER = "manufacturer"
ORG_TYPE_CLIENT = "client"

# Доступ текущего пользователя к машине в ответе API
ACCESS_OWNER = "owner"  # своя org — полные права по роли
ACCESS_MANUFACTURER_READONLY = "manufacturer_readonly"  # проданные — смотреть (+ смена владельца)
ACCESS_PLATFORM = "platform"  # платформенный админ — всё
