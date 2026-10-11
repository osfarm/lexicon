import { memo } from 'react';
import { LexiconCollection } from 'app/components/lexicon_collection';

// The bar of the editor as the Lexicon serves it: the collection being reworked,
// the button that saves it, and where this editor comes from.
export const MenuBar = memo(function MenuBar() {
  return (
    <div className="text-white bg-mb-gray-dark font-sans px-3 flex">
      <a
        className="font-extrabold flex items-center tracking-wide text-base"
        href="/"
      >
        lexicon
      </a>
      <div className="flex items-center pl-3 text-xs">collectes</div>
      <div className="flex-grow flex justify-end">
        <div className="h-[42px]"></div>
        <LexiconCollection />
        <div className="hidden md:flex items-center pl-3 ml-3 border-l border-solid border-gray-700 text-[10px]">
          <a
            href="https://github.com/mapbox/geojson.io"
            target="_blank"
            rel="noopener noreferrer"
          >
            éditeur geojson.io (ISC)
          </a>
        </div>
      </div>
    </div>
  );
});
