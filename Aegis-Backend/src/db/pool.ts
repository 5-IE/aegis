import mysql from 'mysql2/promise';
import { config } from '../lib/config.js';

export const pool = mysql.createPool({
  host: config.db.host,
  port: config.db.port,
  user: config.db.user,
  password: config.db.password,
  database: config.db.name,
  timezone: '+00:00',
  waitForConnections: true,
  connectionLimit: 10,
  namedPlaceholders: true,
});
