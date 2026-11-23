Задача 1 (`GROUP BY` + `HAVING`): Активные города
**Условие:** Вывести города, в которых зарегистрировано больше 10 пользователей, и указать точное количество пользователей в каждом таком городе

SELECT u.city, COUNT(u.id)
FROM users u
GROUP BY u.city
HAVING COUNT(u.id) > 10;

Задача 2 (`JOIN` + `GROUP BY` + `HAVING`): Выручка по категориям товаров
**Условие:** Посчитать общую выручку по каждой категории товаров **только по выполненным (`'completed'`) заказам**. Оставить только те категории, где выручка превысила `15 000`.

SELECT p.category, SUM(p.price * oi.quantity) AS total
FROM order_items AS oi
JOIN products as p
ON p.id = oi.product_id
JOIN orders as o
ON o.id = oi.order_id
WHERE o.status = 'completed'
GROUP BY p.category
HAVING SUM(p.price * oi.quantity) > 15000
ORDER BY total DESC;


Задача 3 (`LEFT JOIN` + `GROUP BY` + `HAVING`): Проблемные товары
**Условие:** Найти товары (`id`, `title`), которые заказывали в составе выполненных заказов **меньше 3 раз** (включая товары, которые не заказывали вообще ни разу).

SELECT p.id, p.title
FROM products p
LEFT JOIN order_items oi
ON oi.product_id = p.id
LEFT JOIN orders o
ON o.id = oi.order_id AND o.status = 'compleated'
GROUP BY p.id, p.title
HAVING COUNT(o.id) < 3
ORDER BY p.id;



Теперь про само приложение. Суть -- пользователи могут размещать свои посты, просмотривать все(заголовоки), выбирать один конкретный, добавлять новые посты, редактировать и удалять -- но только свои. То есть, авторизовался -- можешь что то с постами делать. И тебе на неделю задачи
а) сделать все три задачи по sql, если что то непонятно будет как делать или почему так получилось, пиши
б) сделай proto-файлы для работы внутри приложения, логика которых описана выше. Подумай сам, как лучше разбить по файлам. Скинь мне, если всё ок, сможешь как раз код писать