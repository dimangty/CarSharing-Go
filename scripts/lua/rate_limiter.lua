-- Redis time keeps all gateway instances on the same clock. A unique member
-- preserves concurrent requests that arrive in the same microsecond.
local clock = redis.call("TIME")
local now = tonumber(clock[1]) * 1000000 + tonumber(clock[2])
local window = tonumber(ARGV[2]) * 1000000

redis.call("ZREMRANGEBYSCORE", KEYS[1], "-inf", now - window)
if redis.call("ZCARD", KEYS[1]) >= tonumber(ARGV[1]) then
    return 0
end

redis.call("ZADD", KEYS[1], now, ARGV[3])
redis.call("EXPIRE", KEYS[1], ARGV[2])
return 1
