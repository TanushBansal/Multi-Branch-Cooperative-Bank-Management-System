const $ = (id) => document.getElementById(id);
let config,
  section = 'Banking',
  page = 0,
  prior = new Map(),
  busy = false,
  generation = 0;
const titles = {
  Deposit: 'Deposit money',
  Withdraw: 'Withdraw money',
  Transfer: 'Transfer funds',
  OpenSavingsAccount: 'Open savings account',
  OpenCurrentAccount: 'Open current account',
  OpenFixedDeposit: 'Open fixed deposit',
  ApplyLoan: 'Apply for a loan',
};
async function api(path, options) {
  const response = await fetch(path, options);
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || 'Request failed');
  return data;
}
function label(name) {
  return name
    .replace(/^p_/, '')
    .replace(/_/g, ' ')
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/^./, (s) => s.toUpperCase());
}
function option(value, text) {
  const node = document.createElement('option');
  node.value = value;
  node.textContent = text;
  return node;
}
function renderForm() {
  const op = config.operations.find((o) => o.name === $('operation').value);
  $('fields').replaceChildren();
  if (!op) return;
  $('availability').textContent = op.available
    ? op.name + ' · Installed in MySQL'
    : op.name + ' · Not installed in this database';
  for (const p of op.parameters.filter((p) => p.PARAMETER_MODE === 'IN')) {
    const wrapper = document.createElement('div'),
      caption = document.createElement('label'),
      input = document.createElement('input');
    input.id = 'field-' + p.PARAMETER_NAME;
    input.name = p.PARAMETER_NAME;
    input.required = true;
    caption.htmlFor = input.id;
    caption.textContent = label(p.PARAMETER_NAME);
    if (p.DATA_TYPE === 'date') {
      const now = new Date();
      input.type = 'date';
      input.value = [
        now.getFullYear(),
        String(now.getMonth() + 1).padStart(2, '0'),
        String(now.getDate()).padStart(2, '0'),
      ].join('-');
    } else if (/int|decimal|float|double/.test(p.DATA_TYPE)) {
      input.type = 'text';
      input.inputMode = 'decimal';
      input.pattern = /int/.test(p.DATA_TYPE) ? '[0-9]+' : '[0-9]+(\\.[0-9]{1,2})?';
    }
    if (p.CHARACTER_MAXIMUM_LENGTH) input.maxLength = Number(p.CHARACTER_MAXIMUM_LENGTH);
    if (/request/i.test(p.PARAMETER_NAME)) input.value = crypto.randomUUID();
    if (/channel/i.test(p.PARAMETER_NAME)) input.value = 'BRANCH';
    wrapper.append(caption, input);
    $('fields').append(wrapper);
  }
  $('run').disabled = !op.available || busy;
}
function switchSection(next) {
  section = next;
  document.querySelectorAll('[data-section]').forEach((b) => {
    b.classList.toggle('selected', b.dataset.section === section);
    b.setAttribute('aria-pressed', String(b.dataset.section === section));
  });
  $('section-label').textContent = section.toUpperCase();
  $('heading').textContent = section === 'Banking' ? 'Everyday banking' : 'Loan operations';
  $('description').textContent =
    section === 'Banking'
      ? 'Perform an operation. Refresh the tables to see what changed.'
      : 'Submit an application and inspect the loan lifecycle tables.';
  $('pending').hidden = section !== 'Loans';
  $('operation').replaceChildren(
    ...config.operations
      .filter((o) => o.section === section)
      .map((o) => option(o.name, titles[o.name] || o.name)),
  );
  $('table').value = section === 'Banking' ? 'Account' : 'LoanApplication';
  page = 0;
  renderForm();
  refresh();
}
async function refresh() {
  const version = ++generation,
    table = $('table').value,
    selectedPage = page;
  $('refresh').disabled = true;
  $('table-status').textContent = 'Loading records…';
  $('table-status').className = '';
  try {
    const data = await api(
      '/api/table?name=' + encodeURIComponent(table) + '&page=' + selectedPage,
    );
    if (version !== generation) return;
    const key = table + ':' + selectedPage,
      old = prior.get(key),
      head = document.createElement('tr');
    data.columns.forEach((c) => {
      const th = document.createElement('th');
      th.textContent = c;
      head.append(th);
    });
    $('table-head').replaceChildren(head);
    const records = data.rows.map((row) => {
      const tr = document.createElement('tr');
      const previous = old?.find((r) =>
        data.columns
          .slice(
            0,
            table === 'AccountHolder' ||
              table === 'PaymentAllocation' ||
              table === 'ApplicationGuarantor' ||
              table === 'Nominee'
              ? 2
              : 1,
          )
          .every((c) => r[c] === row[c]),
      );
      data.columns.forEach((c) => {
        const td = document.createElement('td');
        td.textContent = row[c] ?? 'NULL';
        if (old && (!previous || previous[c] !== row[c])) td.className = 'changed';
        tr.append(td);
      });
      return tr;
    });
    if (!records.length) {
      const tr = document.createElement('tr'),
        td = document.createElement('td');
      td.colSpan = data.columns.length || 1;
      td.className = 'empty';
      td.textContent = 'No records on this page.';
      tr.append(td);
      records.push(tr);
    }
    $('table-body').replaceChildren(...records);
    prior.set(key, data.rows);
    $('row-count').textContent = data.total + ' rows';
    $('page-label').textContent = 'Page ' + (page + 1);
    $('previous').disabled = page === 0;
    $('next').disabled = (page + 1) * 50 >= Number(data.total);
    $('refresh-time').textContent = 'Refreshed at ' + new Date().toLocaleTimeString();
    $('table-status').textContent = '';
  } catch (error) {
    if (version === generation) {
      $('table-status').textContent = error.message;
      $('table-status').className = 'error';
    }
  } finally {
    if (version === generation) $('refresh').disabled = false;
  }
}
$('operation-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  if (busy) return;
  busy = true;
  $('run').disabled = true;
  $('operation').disabled = true;
  $('result').className = '';
  $('result').textContent = 'Executing operation…';
  try {
    const values = Object.fromEntries(new FormData(event.target));
    const data = await api('/api/operate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Demo-Token': config.token },
      body: JSON.stringify({ operation: $('operation').value, values }),
    });
    $('result').className = 'success';
    $('result').textContent =
      'Operation completed. Press Refresh to see the changes.\n' +
      data.results
        .flat()
        .map((row) =>
          Object.entries(row)
            .map(([k, v]) => label(k) + ': ' + v)
            .join('\n'),
        )
        .join('\n');
    document.querySelectorAll('#fields input').forEach((input) => {
      if (/request/i.test(input.name)) input.value = crypto.randomUUID();
    });
  } catch (error) {
    $('result').className = 'error';
    $('result').textContent = error.message;
  } finally {
    busy = false;
    $('run').disabled = false;
    $('operation').disabled = false;
  }
});
$('operation').addEventListener('change', renderForm);
$('refresh').addEventListener('click', refresh);
$('table').addEventListener('change', () => {
  page = 0;
  refresh();
});
$('previous').addEventListener('click', () => {
  page = Math.max(0, page - 1);
  refresh();
});
$('next').addEventListener('click', () => {
  page++;
  refresh();
});
document.querySelectorAll('[data-section]').forEach((button) =>
  button.addEventListener('click', () => {
    if (config && !busy) switchSection(button.dataset.section);
  }),
);
async function boot() {
  try {
    config = await api('/api/config');
    $('database').textContent = config.database;
    $('connection').textContent = '● MySQL connected';
    $('table').replaceChildren(...config.tables.map((t) => option(t, t)));
    switchSection(section);
  } catch (error) {
    $('connection').textContent = 'Connection unavailable';
    $('result').className = 'error';
    $('result').textContent = error.message;
    $('run').disabled = true;
  }
}
boot();
