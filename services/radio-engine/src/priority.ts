export type Priority = 'LOW'|'NORMAL'|'HIGH'|'EMERGENCY'|'LIVE';

export const PRIORITY_RANK:Readonly<Record<Priority,number>> = Object.freeze({
  LOW: 10, NORMAL: 20, HIGH: 30, EMERGENCY: 40, LIVE: 50
});

export interface RankedCandidate {
  id:string;
  priority:Priority;
  intendedAt:string;
  createdAt:string;
}

export function compareCandidates(a:RankedCandidate,b:RankedCandidate):number {
  return PRIORITY_RANK[b.priority]-PRIORITY_RANK[a.priority]
    || Date.parse(a.intendedAt)-Date.parse(b.intendedAt)
    || Date.parse(a.createdAt)-Date.parse(b.createdAt)
    || a.id.localeCompare(b.id);
}
