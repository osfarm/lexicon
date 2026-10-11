import { MapContext } from 'app/context/map_context';
import { useImportString } from 'app/hooks/use_import';
import { useZoomTo } from 'app/hooks/use_zoom_to';
import { DEFAULT_IMPORT_OPTIONS } from 'app/lib/convert';
import { getExtent } from 'app/lib/geometry';
import { useAtomCallback } from 'jotai/utils';
import { useCallback, useContext, useEffect, useRef, useState } from 'react';
import toast from 'react-hot-toast';
import { dataAtom } from 'state/jotai';
import { UWrappedFeature } from 'types';

// The collection of the Lexicon this editor was opened on. Its address comes in
// `?collecte=`: a path of this very site, which answers the GeoJSON document
// under `/data` and, under `/session`, the name of the collection, whether it
// may be saved, and the token a change must carry. Nothing is ever read from,
// or sent to, another site.

const COLLECTION_PATH =
  /^\/(account\/collections\/\d{1,18}|collections\/[A-Za-z0-9_-]{22})$/;

type Session = {
  name: string;
  editable: boolean;
  csrf?: string;
  back: string;
};

export function collectionPathIn(search: string): string | null {
  const asked = new URLSearchParams(search).get('collecte');

  return asked !== null && COLLECTION_PATH.test(asked) ? asked : null;
}

export function LexiconCollection() {
  const path = collectionPathIn(window.location.search);
  const map = useContext(MapContext);
  const doImportString = useImportString();
  const zoomTo = useZoomTo();
  const started = useRef(false);
  const [session, setSession] = useState<Session | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (path === null || !map || started.current) return;
    started.current = true;

    void (async () => {
      try {
        const [about, document] = await Promise.all([
          fetch(`${path}/session`, { credentials: 'same-origin' }),
          fetch(`${path}/data`, { credentials: 'same-origin' })
        ]);
        if (!about.ok || !document.ok) {
          throw new Error(
            'Cette collecte est introuvable, ou votre session est terminée.'
          );
        }

        const text = await document.text();
        setSession((await about.json()) as Session);
        await doImportString(
          text,
          { ...DEFAULT_IMPORT_OPTIONS, type: 'geojson' },
          () => {},
          'Collecte'
        );
        zoomTo(getExtent(JSON.parse(text)));
      } catch (error) {
        toast.error(
          error instanceof Error
            ? error.message
            : 'La collecte n’a pas pu être lue.'
        );
      }
    })();
  }, [path, map, doImportString, zoomTo]);

  const save = useAtomCallback(
    useCallback(
      async (get) => {
        if (path === null || session === null || !session.editable) return;
        setSaving(true);

        try {
          const { featureMap } = get(dataAtom);
          const response = await fetch(`${path}/data`, {
            method: 'POST',
            credentials: 'same-origin',
            headers: {
              'Content-Type': 'application/json',
              'X-CSRF-Token': session.csrf ?? ''
            },
            body: JSON.stringify(
              UWrappedFeature.toFeatureCollection(
                Array.from(featureMap.values())
              )
            )
          });
          const answer = (await response.json().catch(() => ({}))) as {
            error?: string;
            features?: number;
          };

          if (!response.ok) {
            throw new Error(
              answer.error ?? 'La collecte n’a pas pu être enregistrée.'
            );
          }
          toast.success(`Collecte enregistrée (${answer.features ?? 0} objets)`);
        } catch (error) {
          toast.error(
            error instanceof Error
              ? error.message
              : 'La collecte n’a pas pu être enregistrée.'
          );
        } finally {
          setSaving(false);
        }
      },
      [path, session]
    )
  );

  if (path === null) {
    return (
      <div className="flex items-center text-xs">
        <a className="underline" href="/account/collections">
          Mes collectes
        </a>
      </div>
    );
  }

  return (
    <div className="flex items-center gap-x-3 text-xs">
      <span className="font-bold truncate max-w-[40vw]">
        {session?.name ?? 'Lecture de la collecte…'}
      </span>
      {session !== null && !session.editable ? (
        <span>lecture seule : vos changements ne sont pas enregistrés</span>
      ) : null}
      {session?.editable ? (
        <button
          className="bg-white text-black font-bold py-1 px-4 rounded disabled:opacity-50"
          disabled={saving}
          onClick={() => void save()}
          type="button"
        >
          {saving ? 'Enregistrement…' : 'Enregistrer'}
        </button>
      ) : null}
      <a className="underline" href={session?.back ?? '/account/collections'}>
        Retour à la collecte
      </a>
    </div>
  );
}
