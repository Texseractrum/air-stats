export const downloadURL = 'https://github.com/Texseractrum/air-stats/releases/latest/download/AirStats.dmg?download=1';

export default {
  fetch(request) {
    if (!['GET', 'HEAD'].includes(request.method)) {
      return new Response(null, { status: 405, headers: { Allow: 'GET, HEAD' } });
    }
    const path = new URL(request.url).pathname;
    if (!['/', '/download', '/AirStats.dmg'].includes(path)) {
      return new Response(request.method === 'HEAD' ? null : 'Not found', { status: 404 });
    }
    return new Response(null, {
      status: 302,
      headers: {
        Location: downloadURL,
        'Cache-Control': 'no-store',
        'Referrer-Policy': 'no-referrer',
        'X-Content-Type-Options': 'nosniff',
        'X-Robots-Tag': 'noindex',
      },
    });
  },
};
