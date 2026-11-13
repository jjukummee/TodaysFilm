"""음성 입력 (3차).

음성 파일 업로드 → 텍스트 전사. 클라이언트는 전사된 텍스트를
답변 입력창에 채워 사용자가 확인/수정 후 저장하게 한다.
(전사 결과를 바로 답변으로 저장하지 않는 이유: STT 오류 검수 기회 제공)
"""
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from ..ai.factory import get_ai_provider
from ..models import User
from ..rate_limit import llm_rate_limit
from ..schemas import TranscriptionOut

router = APIRouter(prefix="/voice", tags=["voice"])

ALLOWED = {
    "audio/mpeg", "audio/mp3", "audio/mp4", "audio/m4a", "audio/x-m4a",
    "audio/wav", "audio/x-wav", "audio/webm", "audio/aac", "audio/ogg",
}
MAX_SIZE = 20 * 1024 * 1024  # 20MB (약 3분 이내 녹음 가정)


@router.post("/transcribe", response_model=TranscriptionOut)
async def transcribe(file: UploadFile = File(...), user: User = Depends(llm_rate_limit)):
    if file.content_type not in ALLOWED:
        raise HTTPException(400, f"지원하지 않는 음성 형식이에요: {file.content_type}")
    audio = await file.read()
    if len(audio) > MAX_SIZE:
        raise HTTPException(400, "음성 파일은 20MB 이하여야 해요.")

    provider = get_ai_provider()
    try:
        text = provider.transcribe(audio, file.content_type)
    except Exception:
        raise HTTPException(502, "음성 인식에 실패했어요. 다시 시도해 주세요.")

    if not text.strip():
        raise HTTPException(422, "음성에서 텍스트를 찾지 못했어요.")
    return TranscriptionOut(text=text.strip())
