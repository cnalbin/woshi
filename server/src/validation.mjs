export class PublicError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

const invalid = (message = '输入格式不正确，请检查后重试。') => {
  throw new PublicError(400, 'INVALID_INPUT', message);
};
function finite(value, min, max) {
  return typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max;
}
function text(value, max) {
  return typeof value === 'string' && value.trim().length > 0 && value.length <= max;
}
function strings(value, maxItems = 8) {
  return Array.isArray(value) && value.length <= maxItems && value.every(v => text(v, 300));
}

export function validateProfile(body) {
  if (!body || !['male', 'female'].includes(body.sex) || !Number.isInteger(body.age)
      || !finite(body.age, 18, 100) || !finite(body.heightCM, 100, 230)
      || !finite(body.weightKG, 25, 300)) {
    invalid('请填写有效的成年用户年龄、性别、身高与体重。');
  }
  // Only the necessary profile fields are forwarded, never arbitrary client data.
  return { sex: body.sex, age: body.age, heightCM: body.heightCM, weightKG: body.weightKG };
}

export function validateMeal(body) {
  if (!body || typeof body.imageBase64 !== 'string' || body.imageBase64.length > 6_000_000
      || !/^[A-Za-z0-9+/]+={0,2}$/.test(body.imageBase64)
      || body.imageBase64.length % 4 !== 0) invalid('请选择有效的照片，压缩后不超过 4 MB。');
  const buffer = Buffer.from(body.imageBase64, 'base64');
  if (buffer.length < 16 || buffer.length > 4_000_000) invalid('照片大小不符合要求。');
  const jpeg = buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
  const png = buffer.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  if (!jpeg && !png) invalid('仅支持 JPEG 或 PNG 图片。');
  if (body.note !== undefined && (typeof body.note !== 'string' || body.note.length > 500)) invalid('补充说明最多 500 字。');
  return { imageBase64: body.imageBase64, mime: jpeg ? 'image/jpeg' : 'image/png', note: body.note?.trim() ?? '' };
}

export function validateResult(kind, output) {
  const bad = () => { throw new PublicError(502, 'INVALID_AI_RESULT', 'AI 返回的结果不完整，请重试或手动记录。'); };
  if (!output || !text(output.summary, 600) || !strings(output.assumptions)) bad();
  if (kind === 'metabolism') {
    if (!finite(output.estimatedKcal, 600, 5000)) bad();
    return { estimatedKcal: output.estimatedKcal, summary: output.summary, assumptions: output.assumptions };
  }
  if (output.isFood === false) throw new PublicError(422, 'NO_FOOD', '照片中没有可识别的食物，请换一张或手动记录。');
  if (output.isFood !== true || !Array.isArray(output.items) || output.items.length < 1
      || output.items.length > 20 || !strings(output.questions)) bad();
  const items = output.items.map(item => {
    if (!item || !text(item.name, 80) || !finite(item.estimatedGrams, 0.1, 10000)
        || !finite(item.estimatedKcal, 0, 10000)) bad();
    return { name: item.name.trim(), estimatedGrams: item.estimatedGrams, estimatedKcal: item.estimatedKcal };
  });
  return { items, summary: output.summary, assumptions: output.assumptions, questions: output.questions };
}
