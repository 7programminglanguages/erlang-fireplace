CREATE TABLE `message_body` (
  `mid` bigint(20) unsigned NOT NULL,
  `body` blob NOT NULL,
  `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `is_del` tinyint(4) unsigned NOT NULL DEFAULT '0' COMMENT '0 - normal, 1 - is deleted by message recall',
  PRIMARY KEY (`mid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 dbpartition by hash(`mid`) tbpartition by hash(`mid`) tbpartitions 256;

CREATE TABLE `message_history` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `uid` bigint(20) unsigned NOT NULL COMMENT 'user id or group id',
  `opposite` bigint(20) unsigned NOT NULL COMMENT 'the opposite user id or group id for this msg',
  `type` char(1) NOT NULL COMMENT '0 - send, 1 - receive',
  `mid` bigint(20) unsigned NOT NULL,
  `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `is_del` tinyint(1) unsigned NOT NULL DEFAULT '0' COMMENT '0 -normal, 1 - is deleted',
  PRIMARY KEY (`id`),
  KEY `i_message_history_uid_opposite_mid` (`uid`,`opposite`,`mid`) USING BTREE,
  KEY `i_message_history_uid_mid` (`uid`,`mid`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 dbpartition by hash(`uid`) tbpartition by hash(`uid`) tbpartitions 256;

CREATE TABLE `message_history_event` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `uid` bigint(20) unsigned NOT NULL,
  `gid` bigint(20) unsigned NOT NULL,
  `type` char(1) NOT NULL COMMENT '0 - enter group, 1 - exit group, 2 - delete group msg',
  `mid` bigint(20) unsigned NOT NULL,
  `timestamp` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `i_message_history_event_uid_gid` (`uid`,`gid`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 dbpartition by hash(`uid`) tbpartition by hash(`uid`) tbpartitions 256;

