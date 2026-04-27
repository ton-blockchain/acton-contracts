import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = path.dirname(fileURLToPath(import.meta.url));

function replaceRegex(source, pattern, replacement, label) {
  if (source.includes(replacement)) {
    return source;
  }

  if (!pattern.test(source)) {
    throw new Error(`Unable to locate ${label}`);
  }

  return source.replace(pattern, replacement);
}

function patchWalletV5(source) {
  if (source.includes('not a cell-like value on a stack')) {
    return source;
  }

  return replaceRegex(
    source,
    /readCell\(\): c\.Cell \{\s*return this\.popExpecting<c\.TupleItemCell>\('cell'\)\.cell;\s*\}/,
    `readCell(): c.Cell {
        const item = this.tuple.shift();
        if (
            item?.type !== 'cell' &&
            item?.type !== 'slice' &&
            item?.type !== 'builder'
        ) {
            throw new Error(\`not a cell-like value on a stack\`);
        }
        return (item as c.TupleItemCell | c.TupleItemSlice | c.TupleItemBuilder).cell;
    }`,
    'WalletV5 StackReader.readCell',
  );
}

function patchSimpleExtension(source) {
  let patched = source;

  if (!patched.includes('not a cell-like value on a stack')) {
    patched = replaceRegex(
      patched,
      /readCell\(\): c\.Cell \{\s*return this\.popExpecting<c\.TupleItemCell>\('cell'\)\.cell;\s*\}/,
      `readCell(): c.Cell {
        const item = this.tuple.shift();
        if (
            item?.type !== 'cell' &&
            item?.type !== 'slice' &&
            item?.type !== 'builder'
        ) {
            throw new Error(\`not a cell-like value on a stack\`);
        }
        return (item as c.TupleItemCell | c.TupleItemSlice | c.TupleItemBuilder).cell;
    }`,
      'SimpleExtension StackReader.readCell',
    );
  }

  if (!patched.includes('readAddress(): c.Address')) {
    patched = replaceRegex(
      patched,
      /readSlice\(\): c\.Slice \{\s*return this\.popExpecting<c\.TupleItemSlice>\('slice'\)\.cell\.beginParse\(\);\s*\}/,
      `readAddress(): c.Address {
        return this.readCell().beginParse().loadAddress();
    }

    readSlice(): c.Slice {
        return this.popExpecting<c.TupleItemSlice>('slice').cell.beginParse();
    }`,
      'SimpleExtension StackReader.readSlice',
    );
  }

  if (!patched.includes('readBigIntOpt(): bigint | null')) {
    patched = replaceRegex(
      patched,
      /readWideNullable<T>\(stackW: number, readFn_T: \(r: StackReader\) => T\): T \| null \{[\s\S]*?this\.tuple\.shift\(\);\s*return valueT;\s*\}/,
      `readBigIntOpt(): bigint | null {
        const item = this.tuple.shift();
        if (item?.type === 'null') {
            return null;
        }
        if (item?.type !== 'int') {
            throw new Error(\`not 'int' on a stack\`);
        }
        return item.value;
    }

    readWideNullable<T>(stackW: number, readFn_T: (r: StackReader) => T): T | null {
        const slotTypeId = this.tuple[stackW - 1];
        if (slotTypeId?.type !== 'int') {
            throw new Error(\`not 'int' on a stack\`);
        }
        if (slotTypeId.value === 0n) {
            this.tuple = this.tuple.slice(stackW);
            return null;
        }
        const valueT = readFn_T(this);
        this.tuple.shift();
        return valueT;
    }

    readNullable<T>(readFn_T: (r: StackReader) => T): T | null {
        return this.readWideNullable(2, readFn_T);
    }`,
      'SimpleExtension StackReader.readWideNullable',
    );
  }

  if (!patched.includes('lastPaymentTime: r.readBigIntOpt()')) {
    patched = replaceRegex(
      patched,
      /walletAddress: r\.readSlice\(\)\.loadAddress\(\),\s*admin: r\.readSlice\(\)\.loadAddress\(\),\s*subscriptionAmount: r\.readBigInt\(\),\s*lastPaymentTime: r\.readNullable<uint32>\(\s*\(r\) => r\.readBigInt\(\)\s*\),\s*paymentTimeInterval: r\.readBigInt\(\),/s,
      `walletAddress: r.readAddress(),
            admin: r.readAddress(),
            subscriptionAmount: r.readBigInt(),
            lastPaymentTime: r.readBigIntOpt(),
            paymentTimeInterval: r.readBigInt(),`,
      'SimpleExtension.getExtensionInfo parser',
    );
  }

  return patched;
}

const wrappers = [
  {
    filename: 'WalletV5.gen.ts',
    patch: patchWalletV5,
  },
  {
    filename: 'SimpleExtension.gen.ts',
    patch: patchSimpleExtension,
  },
];

for (const wrapper of wrappers) {
  const wrapperPath = path.resolve(rootDir, `../wrappers/${wrapper.filename}`);
  const source = fs.readFileSync(wrapperPath, 'utf8');
  const patched = wrapper.patch(source);
  fs.writeFileSync(wrapperPath, patched);
  process.stdout.write(`Patched ${wrapper.filename}\n`);
}
