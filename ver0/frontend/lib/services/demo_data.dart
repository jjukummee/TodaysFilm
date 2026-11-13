// 데모 데이터 — 서버/갤러리 없이 UI를 확인하기 위한 샘플.
// 피그마 디자인의 unsplash 이미지를 그대로 사용.
class DemoFilm {
  final String no, date, title, caption, imageUrl;
  final int day;
  final List<String> keywords;
  const DemoFilm(this.no, this.day, this.date, this.title, this.caption,
      this.imageUrl, this.keywords);
}

const demoFilms = [
  DemoFilm('004', 4, '7. 4 금', '흐린 날의\n산책', '빗소리가 오히려 고요했던',
      'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=280&h=420&fit=crop&auto=format',
      ['산책', '비', '고요']),
  DemoFilm('003', 3, '7. 3 목', '첫 번째\n여름', '창문 너머로 매미 소리를',
      'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=280&h=420&fit=crop&auto=format',
      ['여름', '창문', '산책']),
  DemoFilm('002', 2, '7. 2 수', '조용한\n오후', '커피 한 잔과 책 몇 페이지',
      'https://images.unsplash.com/photo-1509042239860-f550ce710b93?w=280&h=420&fit=crop&auto=format',
      ['카페', '책', '고요']),
  DemoFilm('001', 1, '7. 1 화', '월요일의\n창문', '빗방울이 유리 위를 지나가던',
      'https://images.unsplash.com/photo-1519974719765-e6559eac2575?w=280&h=280&fit=crop&auto=format',
      ['비', '창문', '카페']),
];

const demoGalleryUrls = [
  'https://images.unsplash.com/photo-1502082553048-f009c37129b9?w=280&h=280&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1519681393784-d120267933ba?w=280&h=280&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1445205170230-053b83016050?w=280&h=280&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1508921912186-1d1a45ebb3c1?w=280&h=280&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1490750967868-88aa4486c946?w=280&h=280&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1493246507139-91e8fad9978e?w=280&h=280&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1500534314209-a25ddb2bd429?w=280&h=280&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=280&h=280&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=280&h=280&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1509042239860-f550ce710b93?w=280&h=280&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1519638399535-1b036603ac77?w=280&h=280&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1504700610630-ac6aba3536d3?w=280&h=280&fit=crop&auto=format',
];

const demoQuestions = [
  '이 사진을 오늘의 대표 장면으로 고른 이유가 있을까요?',
  '그 순간에서 가장 오래 기억하고 싶은 것은 무엇인가요?',
  '오늘 하루를 영화의 한 장면으로 남긴다면 어떤 장면으로 기억하고 싶나요?',
];

const demoFilmResult = {
  'film_title': '별일 없어서 더 오래 남은 하루',
  'ending_narration': '오늘은 특별한 사건보다 편안한 웃음과 조용한 시간이 더 오래 남은 하루였다.',
  'representative_sentence': '아무 말 없이 있어도 괜찮았던 순간이 가장 좋았다.',
  'keywords': ['친구', '편안함', '웃음', '카페'],
};
