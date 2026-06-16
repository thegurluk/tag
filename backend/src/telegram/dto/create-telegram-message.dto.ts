import { Transform } from 'class-transformer';
import { IsDateString, IsNotEmpty, IsOptional, IsString } from 'class-validator';

const toBigInt = ({ value }: { value: string | number | bigint }) =>
  typeof value === 'bigint' ? value : BigInt(value);

export class CreateTelegramMessageDto {
  @Transform(toBigInt)
  telegram_message_id!: bigint;

  @Transform(toBigInt)
  telegram_group_id!: bigint;

  @IsOptional()
  @Transform(({ value }) => (value === null || value === undefined ? null : BigInt(value)))
  sender_id?: bigint | null;

  @IsString()
  @IsNotEmpty()
  raw_text!: string;

  @IsDateString()
  received_at!: string;
}
