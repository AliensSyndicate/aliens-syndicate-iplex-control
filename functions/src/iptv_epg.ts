import {XMLParser, XMLValidator} from 'fast-xml-parser';
import {DomainError} from './domain';

export type IptvProgramme = {channelId: string; title: string; startAt: number; endAt: number; description: string};
export function xmltvTime(raw: string): number {
  const parts = /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\s*([+-])(\d{2})(\d{2})$/.exec(raw);
  if (!parts) throw new DomainError('invalid-epg');
  const [, y, m, d, h, min, sec, sign, oh, om] = parts;
  const date = new Date(Date.UTC(+y!, +m! - 1, +d!, +h!, +min!, +sec!));
  if (date.getUTCFullYear() !== +y! || date.getUTCMonth() !== +m! - 1 || date.getUTCDate() !== +d! || +h! > 23 || +min! > 59 || +sec! > 59 || +oh! > 14 || +om! > 59) throw new DomainError('invalid-epg');
  return date.getTime() - (sign === '+' ? 1 : -1) * (+oh! * 60 + +om!) * 60000;
}
export function parseIptvEpg(xml: string): IptvProgramme[] {
  if (Buffer.byteLength(xml, 'utf8') > 20 * 1024 * 1024 || /<!DOCTYPE|<!ENTITY/i.test(xml) || XMLValidator.validate(xml) !== true) throw new DomainError('invalid-epg');
  const data = new XMLParser({ignoreAttributes: false, parseTagValue: false, processEntities: false, isArray: (_name, path) => path === 'tv.programme'}).parse(xml);
  if (!data.tv || !Array.isArray(data.tv.programme) || data.tv.programme.length > 100000) throw new DomainError('invalid-epg');
  const text = (value: any): string => String((Array.isArray(value) ? value[0] : value)?.['#text'] ?? (Array.isArray(value) ? value[0] : value) ?? '');
  return data.tv.programme.map((row: any) => {
    const channelId = String(row['@_channel'] ?? ''), title = text(row.title).slice(0, 300);
    const startAt = xmltvTime(String(row['@_start'])), endAt = xmltvTime(String(row['@_stop']));
    if (!channelId || channelId.length > 300 || !title || endAt <= startAt) throw new DomainError('invalid-epg');
    return {channelId, title, startAt, endAt, description: text(row.desc).slice(0, 2000)};
  });
}
